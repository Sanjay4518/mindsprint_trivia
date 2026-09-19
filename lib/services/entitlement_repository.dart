import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'billing_service.dart';
import 'player_service.dart';

/// Tracks whether the player currently has an active real Premium
/// subscription, and ties that to their signed-in Google identity (per the
/// locked-in decision: real Premium purchases require Google sign-in
/// first) rather than just something cached on one device.
///
/// Entitlement source of truth: Google Play itself, via
/// [BillingService.restorePurchases] -- Play's own client library talks to
/// Google's servers to report currently-owned purchases, so this reflects
/// real subscription status (active/cancelled/expired), not just "did they
/// ever buy it once." A Firestore mirror is kept too, both so a signed-in
/// player's status is visible in their own profile data if this app ever
/// reads it back on another device, and so a future server-side check
/// (see note below) would have something to build on.
///
/// Known limitation, by design for v1: this checks entitlement from the
/// client, not a server. That's standard practice for a solo/indie app and
/// is reasonably solid (Play's own restore call is authoritative for
/// "currently owned"), but a determined attacker with a rooted/modified
/// device could theoretically fool the client. A fully server-verified
/// version -- a Firebase Cloud Function calling the Google Play Developer
/// API, ideally driven by Play's Real-time Developer Notifications -- is a
/// stronger future upgrade once there's real revenue worth protecting
/// further. It requires Firebase's Blaze (pay-as-you-go) plan enabled for
/// Cloud Functions -- a deliberate step Sanjay would need to take, not
/// something to switch on quietly as part of this change.
class EntitlementRepository {
  static final _db = FirebaseFirestore.instance;
  static bool _sawActiveDuringLastRestore = false;

  // refreshEntitlement() is called from both the splash-screen startup
  // path and every Home-screen refresh (initState + after every
  // navigation return), so two calls can easily overlap on a cold start.
  // _sawActiveDuringLastRestore is a single static flag shared by every
  // caller -- without serializing calls, one call's "reset the flag to
  // false" can run after another call's "Play told us it's active" already
  // set it true, and both then see false and race toward revoking a
  // perfectly active subscriber. Funnelling every call through the same
  // in-flight Future makes overlapping calls share one outcome instead.
  static Future<void>? _inFlight;

  /// Called by [BillingService] whenever it sees an active/restored
  /// purchase for the monthly subscription. Marks Premium active locally
  /// (immediately, so the player doesn't wait on a network round trip to
  /// use what they just paid for) and mirrors the purchase to Firestore.
  static Future<void> recordActiveSubscription(
    PurchaseDetails purchase,
  ) async {
    _sawActiveDuringLastRestore = true;
    await _clearMissedChecks();

    await PlayerService.setSubscriptionPremiumActive(true);

    final uid = AuthService.uid;
    if (uid == null) return;

    try {
      await _db.collection('users').doc(uid).set({
        'premiumSubscriptionActive': true,
        'premiumSubscriptionProductId': purchase.productID,
        'premiumSubscriptionPurchaseId': purchase.purchaseID,
        'premiumSubscriptionLastVerified': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignored -- the part that actually gates gameplay (the local flag
      // above) is already updated regardless of whether this mirror
      // write succeeds.
    }
  }

  /// Re-checks real subscription status against Play Store. Safe to call
  /// often (app startup, every Home refresh) -- cheap, never blocks
  /// gameplay if it fails or times out.
  ///
  /// Deliberately conservative about revoking access: local Premium only
  /// gets turned off after TWO separate checks in a row both come back
  /// empty (a small counter persisted in SharedPreferences, surviving
  /// across app restarts). This means a single flaky/slow network moment
  /// can never wrongly kick a paying subscriber out of Premium -- a
  /// genuinely cancelled/expired subscription still gets caught within a
  /// couple of app opens, which is more than good enough for this.
  static Future<void> refreshEntitlement() {
    // If a check is already running, piggyback on it instead of starting a
    // second one that could race the first's flag reset.
    return _inFlight ??= _refreshEntitlement().whenComplete(
      () => _inFlight = null,
    );
  }

  static Future<void> _refreshEntitlement() async {
    if (AuthService.uid == null) return;
    if (!BillingService.storeAvailable) return;

    _sawActiveDuringLastRestore = false;
    final bool queryCompleted = await BillingService.restorePurchases();

    // Gives the purchase stream a moment to deliver anything Play reports
    // as currently owned -- restorePurchases() itself only confirms the
    // request was sent, not that every result has arrived yet.
    await Future.delayed(const Duration(seconds: 2));

    if (_sawActiveDuringLastRestore) return;

    // The query never actually reached Play (offline, Play Services
    // couldn't answer). "We couldn't ask" is not evidence that the
    // subscription is gone, so this attempt doesn't count as a missed
    // check at all -- otherwise two app opens with no signal would revoke
    // a paying subscriber's Premium, which is exactly what this method's
    // own doc comment above promises can never happen. Note that
    // storeAvailable reflects Play Services being present on the device,
    // not connectivity, so the early return above does NOT cover this.
    if (!queryCompleted) return;

    // Nothing came back this time. Only someone who's actually had an
    // active subscription before has anything to lose here -- a brand new
    // free player just quietly stays not-subscribed, no counter needed.
    if (!PlayerService.hasActiveSubscription) return;

    final missed = await _recordMissedCheck();
    if (missed >= 2) {
      await _revokeSubscriptionEntitlement();
    }
  }

  static Future<int> _recordMissedCheck() async {
    final prefs = await SharedPreferences.getInstance();
    final missed = (prefs.getInt('subMissedChecks') ?? 0) + 1;
    await prefs.setInt('subMissedChecks', missed);
    return missed;
  }

  static Future<void> _clearMissedChecks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('subMissedChecks', 0);
  }

  static Future<void> _revokeSubscriptionEntitlement() async {
    await PlayerService.setSubscriptionPremiumActive(false);

    final uid = AuthService.uid;
    if (uid == null) return;

    try {
      await _db.collection('users').doc(uid).set({
        'premiumSubscriptionActive': false,
        'premiumSubscriptionLastVerified': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignored -- see comment in recordActiveSubscription.
    }
  }
}
