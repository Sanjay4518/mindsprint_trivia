import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'entitlement_repository.dart';

/// Wraps Google Play Billing for the real Premium monthly subscription.
///
/// IMPORTANT for Sanjay -- read before testing: none of this can be tried
/// on-device until a matching subscription product exists in Play Console.
/// Go to Play Console -> your app -> Monetize -> Products -> Subscriptions
/// -> Create subscription, and use the product ID [monthlySubscriptionId]
/// below exactly (`premium_monthly`) -- or, if you'd rather choose your
/// own ID, create it however you like and just update the constant to
/// match. Add one base plan (auto-renewing, monthly, your ₹100-150 price),
/// activate it, and add your own Google account as a license tester
/// (Play Console -> Setup -> License testing) so test purchases show a
/// real-looking purchase flow without actually charging a card. A
/// subscription product also needs the app itself to have at least one
/// release uploaded to Play Console (Internal testing counts) before the
/// product will actually load in-app -- if `buyMonthlySubscription()`
/// keeps failing quietly, that's the most likely reason.
class BillingService {
  static const String monthlySubscriptionId = 'premium_monthly';

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _subscription;
  static bool _initialized = false;

  /// True once the device's Play Store connection is confirmed available.
  /// If false, purchasing isn't possible right now (no Play Store on this
  /// device, or Play Services unavailable -- e.g. some emulators).
  static bool storeAvailable = false;

  static ProductDetails? _cachedProduct;

  /// The loaded subscription product (price, etc.), or null if it hasn't
  /// loaded yet -- either because [initialize] hasn't run, the device is
  /// offline, or (most likely during development) the product doesn't
  /// exist in Play Console yet under [monthlySubscriptionId].
  static ProductDetails? get cachedProduct => _cachedProduct;

  /// Sets up the purchase-update listener once for the whole app lifetime
  /// and loads the real subscription price from Play Store. Safe to call
  /// more than once -- only does real work the first time. Never throws;
  /// if anything here fails the Premium screen just falls back to a
  /// generic "Subscribe" button without a live price.
  static Future<void> initialize() async {
    if (_initialized) return;

    try {
      storeAvailable = await _iap.isAvailable();
    } catch (_) {
      storeAvailable = false;
    }

    // Deliberately NOT marking _initialized here if the store isn't
    // available yet -- this used to be set unconditionally before the
    // check above, which meant a single bad launch (offline, Play
    // Services still settling after a reboot, the Play Store app
    // mid-update) permanently disabled purchasing for the rest of that
    // app session with no error the player could act on: buying returned
    // false silently, and entitlement refreshes kept short-circuiting.
    // Leaving _initialized false lets a later call (the next Home refresh,
    // the next time the Premium screen opens) retry for real once
    // connectivity/Play Services recovers.
    if (!storeAvailable) return;
    _initialized = true;

    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (_) {
        // Ignored -- a stream hiccup just means we might miss an update;
        // the next EntitlementRepository.refreshEntitlement() call (app
        // start / Home refresh) re-checks from scratch regardless.
      },
    );

    await _loadProduct();
  }

  /// Stops listening for purchase updates. Not currently called anywhere
  /// (the listener is meant to live for the whole app session), but kept
  /// available so the subscription field is properly used rather than
  /// flagged as dead by the analyzer, and so a future screen that wants
  /// to tear billing down cleanly has a way to do it.
  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  static Future<void> _loadProduct() async {
    try {
      final response = await _iap.queryProductDetails({
        monthlySubscriptionId,
      });
      if (response.productDetails.isNotEmpty) {
        _cachedProduct = response.productDetails.first;
      }
      // If response.notFoundIDs contains monthlySubscriptionId, the
      // product isn't set up (or isn't active) in Play Console yet --
      // expected during development, not an app bug.
    } catch (_) {
      // Offline, or Play Store unreachable.
    }
  }

  /// Starts the purchase flow for the monthly subscription. Returns false
  /// immediately (without showing anything) if the store isn't available
  /// or the product hasn't loaded -- callers should show a friendly
  /// message in that case rather than assume it always works.
  static Future<bool> buyMonthlySubscription() async {
    if (!storeAvailable) return false;

    var product = _cachedProduct;
    if (product == null) {
      await _loadProduct();
      product = _cachedProduct;
    }
    if (product == null) return false;

    PurchaseParam purchaseParam;

    // Modern Play subscriptions are sold as "offers" under a base plan
    // (Play Console's current subscription model). This app only has one
    // simple monthly plan with no introductory/trial tiers. The plugin
    // already resolves the right offer token for us: queryProductDetails
    // returns one GooglePlayProductDetails per offer, each carrying its
    // own [offerToken] getter -- no need to dig into the raw
    // subscriptionOfferDetails list ourselves.
    if (product is GooglePlayProductDetails && product.offerToken != null) {
      purchaseParam = GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: product.offerToken,
      );
    } else {
      purchaseParam = PurchaseParam(productDetails: product);
    }

    try {
      // Subscriptions go through the same non-consumable purchase entry
      // point in this plugin's unified API -- there's no separate
      // "buySubscription" method.
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (_) {
      return false;
    }
  }

  /// Asks Play Store to report the player's currently-owned purchases.
  /// This is the real "is the subscription still active" check -- Play's
  /// own client library talks to Google's servers to answer it, so it
  /// reflects true current status (active/cancelled/expired), not just a
  /// value cached from whenever it was first bought. Results arrive
  /// asynchronously through [purchaseStream] -- see
  /// [EntitlementRepository.refreshEntitlement] for how those are turned
  /// into an actual entitlement decision.
  /// Returns true only if the query itself actually completed. A false
  /// result means "we couldn't ask Play right now" -- NOT "Play says you
  /// own nothing." Callers must never treat those the same: collapsing
  /// the two is what allowed two offline app opens to revoke a paying
  /// subscriber's Premium (see EntitlementRepository._refreshEntitlement).
  ///
  /// Note a successful query that reports no purchases still returns true
  /// -- that's a real answer from Play, and it's how a genuinely
  /// cancelled or expired subscription gets caught.
  static Future<bool> restorePurchases() async {
    if (!storeAvailable) return false;
    try {
      await _iap.restorePurchases();
      return true;
    } catch (_) {
      // Offline, or Play Services couldn't answer -- the caller skips its
      // entitlement check entirely rather than counting this as evidence.
      return false;
    }
  }

  static Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.productID != monthlySubscriptionId) continue;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await EntitlementRepository.recordActiveSubscription(purchase);
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;

        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          // A failed/cancelled purchase attempt -- entitlement stays
          // whatever it already was; nothing to record.
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
          break;
      }
    }
  }
}
