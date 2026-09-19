import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';

/// Provides a "now" that can't be fooled by changing the phone's own clock.
///
/// Two things in the app used to trust `DateTime.now()` directly:
/// - Stamina regeneration (1 stamina every 4 minutes) -- a player could push
///   their phone's clock forward and instantly refill stamina for free.
/// - Temporary Premium's expiry (from watching a rewarded ad, or the one-time
///   Google sign-in bonus) -- a player could roll their phone's clock
///   backward right before it expired, freezing the countdown and keeping
///   Premium active indefinitely.
///
/// Firestore's `FieldValue.serverTimestamp()` is stamped by Google's own
/// servers when the write is committed, not by the device, so comparing
/// against that instead closes both holes.
///
/// This deliberately does NOT make every stamina/Premium check an async
/// network call (that would touch a huge number of call sites and add
/// latency to things like just showing "Premium active" in the UI). Instead
/// it keeps a lightweight cached offset between the device clock and the
/// server clock, refreshed at the moments that actually matter: app
/// startup, every time the Home screen data refreshes (i.e. constantly,
/// between every action), and right before anything stamina/Premium-gated
/// actually happens (entering a quiz mode, granting a temporary-Premium
/// reward). That keeps the window for a clock trick to slip through
/// vanishingly small without rewriting the whole app to be async.
class ServerTimeService {
  static Duration _offset = Duration.zero;
  static DateTime? _lastSynced;

  // sync() is called from HomeScreen.refreshData() (unawaited, on every
  // refresh) AND awaited at several ModeEntryHelper call sites right before
  // a stamina/Premium-gated action -- so a resume-from-background refresh
  // and an immediate "Play" tap can genuinely overlap. Same reasoning and
  // same "piggyback on the in-flight call" fix as
  // EntitlementRepository.refreshEntitlement() (see that file): without
  // this, two concurrent network round-trips could finish out of order,
  // and whichever happens to resolve *last* -- not whichever is actually
  // more current -- would win and set `_offset`/`_lastSynced`. Since
  // `_offset` is the sole defense against device-clock tampering for
  // stamina regen and temp-Premium expiry, a stale response clobbering a
  // fresher one briefly reopens exactly the hole this service exists to
  // close.
  static Future<void>? _inFlight;

  /// "Now," corrected for the device-vs-server offset. Falls back to the
  /// plain device clock if we've never synced yet (e.g. brand new install,
  /// still offline) -- same "never block gameplay" philosophy used
  /// elsewhere in the app. This is intentionally synchronous/instant so it
  /// can be dropped in anywhere `DateTime.now()` used to be used.
  static DateTime now() => DateTime.now().add(_offset);

  /// Refreshes the cached offset against Firebase's server clock. Cheap --
  /// one small write + read to the player's own `users/{uid}` document
  /// (already allowed by the existing Firestore security rules, so no rule
  /// changes are needed) -- and safe to call often. Silently does nothing
  /// if there's no signed-in user yet or the device is offline; the last
  /// known offset (or none) just keeps being used.
  static Future<void> sync() {
    // If a sync is already running, piggyback on it instead of starting a
    // second one that could race the first and clobber it with a stale
    // result (see the doc comment on _inFlight above).
    return _inFlight ??= _sync().whenComplete(() => _inFlight = null);
  }

  static Future<void> _sync() async {
    final uid = AuthService.uid;
    if (uid == null) return;

    try {
      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      final beforeWrite = DateTime.now();

      // Both calls are time-bounded on purpose. A Firestore write's Future
      // only resolves once the backend acknowledges it -- while offline it
      // applies to the local cache instantly but the Future itself just
      // never completes (it doesn't throw), so without this timeout a
      // player with no connectivity would hang here indefinitely. Since
      // this method is awaited on the splash screen's critical startup
      // path (and before every mode entry), that used to mean the app
      // never got past the loading spinner at all with no network. The
      // outer catch below already treats any failure the same way (keep
      // whatever offset we had), so a timeout here is handled identically
      // to any other sync failure.
      await ref
          .set({
            '_serverTimeCheck': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 5));

      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 5));
      final serverTs = (snap.data()?['_serverTimeCheck'] as Timestamp?)
          ?.toDate();
      if (serverTs == null) return;

      // Rough latency correction: assume the server stamped the write
      // roughly halfway through the round trip.
      final roundTrip = DateTime.now().difference(beforeWrite);
      final estimatedServerNow = serverTs.add(roundTrip ~/ 2);

      _offset = estimatedServerNow.difference(DateTime.now());
      _lastSynced = DateTime.now();
    } catch (_) {
      // Offline, not signed in yet, or a Firestore hiccup -- keep using
      // whatever offset (or none) we already had rather than blocking
      // anything the player is trying to do.
    }
  }

  /// Whether we have a reasonably fresh offset (synced in the last 10
  /// minutes). Not currently used to block anything -- available if a
  /// future check wants to be stricter (e.g. refuse a reward if the offset
  /// is stale rather than trusting a long-cached value).
  static bool get hasSyncedRecently =>
      _lastSynced != null &&
      DateTime.now().difference(_lastSynced!) < const Duration(minutes: 10);
}
