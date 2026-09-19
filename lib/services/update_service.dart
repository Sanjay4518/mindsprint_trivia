import 'package:flutter/foundation.dart' show debugPrint;
import 'package:in_app_update/in_app_update.dart';

/// Wraps Google Play's In-App Updates API (flexible mode only -- see the
/// doc comment on [checkAndStartFlexibleUpdate] for why immediate/blocking
/// updates are deliberately never used) so a player who already has this
/// app installed gets prompted to update from inside the app itself,
/// instead of relying on them noticing a Play Store update manually.
///
/// Works on every Play release track (Internal/Closed/Open Testing and
/// Production alike) -- Play evaluates update availability for the signed-
/// in account/device against whatever's currently live on the same track
/// that install came from, not "Production only".
///
/// Important limitation, not a bug: this can only ever reach players who
/// already have a build that *includes this code*. It cannot retroactively
/// reach anyone already on v1.0.0+13 or earlier -- those installs have no
/// idea this feature exists yet. The first release that ships this still
/// needs the usual "please update" ask; every release after that can
/// prompt automatically.
class UpdateService {
  // Guards against calling checkForUpdate()/startFlexibleUpdate() more than
  // once per app process. Both SplashScreen (fires this as early as
  // possible, same as AdService/BillingService/NotificationService.init())
  // and HomeScreen (awaits it again from initState to know when to show the
  // restart prompt) call the public method here -- without this, HomeScreen
  // could kick off a second, redundant check/download on top of one Splash
  // already started. Same piggyback-Future shape as NotificationService.
  // init()/ServerTimeService.sync() elsewhere in this app.
  static Future<bool>? _inFlight;
  static bool _downloadedAndReady = false;

  /// True once a flexible update has finished downloading and is just
  /// waiting for [completeUpdate] to actually install/restart. Exposed
  /// mainly so a caller can check without awaiting a fresh network round-
  /// trip, though [checkAndStartFlexibleUpdate] already returns instantly
  /// once this is true.
  static bool get updateReadyToInstall => _downloadedAndReady;

  /// Checks Play for a newer version and, if one exists and a flexible
  /// (non-blocking) update is allowed, starts downloading it in the
  /// background. The returned future only completes once that download has
  /// actually finished (or Play reports no update / only immediate is
  /// allowed) -- callers are expected to await this unawaited-from-
  /// initState (see HomeScreen), never block anything on it. Returns true
  /// once ready to install, so the caller can show a "Restart to update"
  /// prompt and call [completeUpdate] if the player accepts.
  ///
  /// Deliberately only acts on [AppUpdateInfo.flexibleUpdateAllowed], never
  /// [AppUpdateInfo.immediateUpdateAllowed] -- an immediate update hands
  /// control to Play's own full-screen blocking UI until it finishes, which
  /// would be a much worse experience here (could land mid-quiz) than a
  /// quiet background download the player accepts on their own schedule
  /// from Home. If Play only ever offers immediate for some future release
  /// (e.g. it gets marked high-priority in Play Console), this just does
  /// nothing rather than forcing that flow -- nothing today sets an update
  /// priority, so this shouldn't come up in practice.
  static Future<bool> checkAndStartFlexibleUpdate() {
    if (_downloadedAndReady) return Future.value(true);
    return _inFlight ??= _check().whenComplete(() => _inFlight = null);
  }

  static Future<bool> _check() async {
    try {
      final AppUpdateInfo info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability != UpdateAvailability.updateAvailable ||
          !info.flexibleUpdateAllowed) {
        return false;
      }
      // Completes once the update has actually finished downloading (per
      // the in_app_update package's own documented behavior) -- not just
      // once the download has started. Safe to await for however long that
      // takes: both call sites run this unawaited, so normal gameplay
      // elsewhere in the app is completely unaffected while it's in
      // progress.
      await InAppUpdate.startFlexibleUpdate();
      _downloadedAndReady = true;
      return true;
    } catch (e) {
      // Never let a Play Store/network hiccup here affect the app itself --
      // worst case, no update prompt shows this session, same as if this
      // feature didn't exist. This also fires on every non-Play install
      // (a raw debug/sideloaded build, or `flutter run`), which is expected
      // and not worth its own separate check -- the API just isn't
      // available there. debugPrint is diagnostic only (throttled/stripped
      // for release, never shown to a player).
      debugPrint('UpdateService.checkAndStartFlexibleUpdate() failed: $e');
      return false;
    }
  }

  /// Actually installs the already-downloaded update and restarts the app.
  /// Only meaningful after [checkAndStartFlexibleUpdate] has returned true;
  /// calling this with nothing downloaded is a safe no-op per the
  /// underlying Play Core API, so no extra guard is needed here.
  static Future<void> completeUpdate() async {
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('UpdateService.completeUpdate() failed: $e');
    }
  }
}
