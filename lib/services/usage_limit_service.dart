import 'package:shared_preferences/shared_preferences.dart';
import 'server_time_service.dart';

class UsageLimitService {
  // NOTE (2026-07-26): the old flat daily caps (40 Normal Mode questions/day,
  // 2 Rapid Fire rounds/day) were removed. They duplicated -- and undercut --
  // the stamina system, which is the actual intended pacing mechanic: stamina
  // already limits free play, regenerates over time, and can be refilled via
  // ads or Premium. A separate hard daily count on top of that meant a player
  // could refill their stamina and still be blocked, which defeated the
  // point of the ad-refill feature. Stamina alone now gates Normal Mode and
  // Rapid Fire entry for free users.
  static const int freeTempPremiumUnlocksPerDay = 2;

  // Daily cap on rewarded-ad stamina refills (+20 stamina/ad, see
  // ModeEntryHelper). Added 2026-09-02 -- this used to be completely
  // uncapped, letting a free player bypass the whole stamina economy for
  // the cost of one ~30s ad per game, unlike every other rewarded-ad
  // mechanic in the app which is deliberately capped.
  static const int freeStaminaAdsPerDay = 3;

  /// Serialises every read-modify-write against each other -- same bug
  /// class and same fix as PlayerService's/StaminaService's identical
  /// `_prefsChain`/`_serialised` (see StaminaService for the full
  /// reasoning). This service has just as many uncoordinated call sites
  /// touching the same three SharedPreferences keys: ModeEntryHelper's
  /// rewarded-ad flows (recordTempPremiumUnlockWatched/
  /// recordStaminaAdWatched), and PlayerRepository's cloud-restore merge
  /// and sync snapshot (mergeFromCloud/snapshotForSync, both of which also
  /// run _resetIfNeeded as a side effect). Any two of these can genuinely
  /// overlap -- e.g. a cloud restore retried from Profile while an ad
  /// reward from a just-finished round is still being recorded. Without
  /// this, a torn interleave could silently stomp a just-recorded ad watch
  /// back to a stale count, handing out one extra free unlock for that day.
  /// Not locking, just queuing -- each call simply runs after whatever's
  /// already pending.
  static Future<void> _prefsChain = Future.value();

  static Future<T> _serialised<T>(Future<T> Function() action) {
    final Future<T> result = _prefsChain.then((_) => action());
    _prefsChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static String _todayKey() {
    // Server-corrected time, not the raw device clock -- everything else
    // that needs clock-tamper resistance (stamina regen, temp-Premium
    // expiry) already goes through ServerTimeService. This counter was
    // the one place still trusting DateTime.now() directly, which meant
    // rolling the device's date forward a day reset the daily temp-Premium
    // ad-unlock cap for free, indefinitely.
    //
    // .toUtc() matters as much as the offset does. The offset defends
    // against a wrong *clock*, but the day fields were still read off a
    // local DateTime -- so simply moving the device's timezone far enough
    // east rolled this key to the next date and granted a fresh set of
    // daily ad unlocks, repeatable as often as the player liked, with no
    // clock change for ServerTimeService to catch.
    //
    // Trade-off worth knowing: the allowance now resets at one fixed
    // worldwide moment (00:00 UTC, which is 05:30 in IST) rather than at
    // each player's local midnight. For this audience that lands in the
    // small hours either way, and it's the only version of this that a
    // player can't move at will. Existing installs may see one extra
    // reset the first time this runs, if their stored key was a local
    // date that differs from today's UTC date -- harmless, it just grants
    // that day's allowance once more.
    final now = ServerTimeService.now().toUtc();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  static Future<void> _resetIfNeeded(SharedPreferences prefs) async {
    final today = _todayKey();
    final savedDate = prefs.getString("usageDate");

    if (savedDate == today) return;

    await prefs.setString("usageDate", today);
    await prefs.setInt("tempPremiumUnlocksToday", 0);
    await prefs.setInt("staminaAdsToday", 0);
  }

  /// How many times today the player has already watched an ad to unlock
  /// a temporary Premium window. Resets daily, same as the other counters
  /// on this page.
  static Future<int> getTempPremiumUnlocksToday() =>
      _serialised(_getTempPremiumUnlocksToday);

  static Future<int> _getTempPremiumUnlocksToday() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    return prefs.getInt("tempPremiumUnlocksToday") ?? 0;
  }

  static Future<bool> canWatchTempPremiumAd() =>
      _serialised(_canWatchTempPremiumAd);

  static Future<bool> _canWatchTempPremiumAd() async {
    return await _getTempPremiumUnlocksToday() < freeTempPremiumUnlocksPerDay;
  }

  static Future<void> recordTempPremiumUnlockWatched() =>
      _serialised(_recordTempPremiumUnlockWatched);

  static Future<void> _recordTempPremiumUnlockWatched() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    final used = prefs.getInt("tempPremiumUnlocksToday") ?? 0;
    await prefs.setInt("tempPremiumUnlocksToday", used + 1);
  }

  /// How many rewarded-ad stamina refills the player has already watched
  /// today. Resets daily, same as the temp-Premium ad counter above.
  static Future<int> getStaminaAdsToday() => _serialised(_getStaminaAdsToday);

  static Future<int> _getStaminaAdsToday() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    return prefs.getInt("staminaAdsToday") ?? 0;
  }

  static Future<bool> canWatchStaminaAd() => _serialised(_canWatchStaminaAd);

  static Future<bool> _canWatchStaminaAd() async {
    return await _getStaminaAdsToday() < freeStaminaAdsPerDay;
  }

  static Future<void> recordStaminaAdWatched() =>
      _serialised(_recordStaminaAdWatched);

  static Future<void> _recordStaminaAdWatched() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    final used = prefs.getInt("staminaAdsToday") ?? 0;
    await prefs.setInt("staminaAdsToday", used + 1);
  }

  /// Raw snapshot of today's counters for [PlayerRepository.syncCurrentPlayer]
  /// to push to the cloud. Always reads fresh from SharedPreferences (there's
  /// no in-memory cache on this service), so this is safe to call at any
  /// point in app startup regardless of what else has run yet.
  static Future<Map<String, dynamic>> snapshotForSync() =>
      _serialised(_snapshotForSync);

  static Future<Map<String, dynamic>> _snapshotForSync() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    return {
      'usageDate': prefs.getString("usageDate"),
      'tempPremiumUnlocksToday': prefs.getInt("tempPremiumUnlocksToday") ?? 0,
      'staminaAdsToday': prefs.getInt("staminaAdsToday") ?? 0,
    };
  }

  /// Cloud-restore support (see PlayerRepository.restorePlayerFromCloud) --
  /// merges today's daily-cap counters with a cloud snapshot, so
  /// uninstalling and reinstalling can't reset either daily ad cap for
  /// free. This used to be masked by Android Auto Backup accidentally
  /// restoring the whole local profile on reinstall; now that Auto Backup
  /// is correctly disabled, this cloud merge is what actually closes that
  /// loophole.
  ///
  /// Only applies the cloud side if it's for the SAME calendar day as this
  /// device's -- a stale cloud snapshot from a previous day must never
  /// suppress today's real reset. When both sides are for today, takes the
  /// max of each counter (never regresses either cap -- safe even if this
  /// runs more than once, e.g. a retried restore).
  static Future<void> mergeFromCloud({
    required String? cloudUsageDate,
    required int cloudTempPremiumUnlocksToday,
    required int cloudStaminaAdsToday,
  }) => _serialised(
    () => _mergeFromCloud(
      cloudUsageDate: cloudUsageDate,
      cloudTempPremiumUnlocksToday: cloudTempPremiumUnlocksToday,
      cloudStaminaAdsToday: cloudStaminaAdsToday,
    ),
  );

  static Future<void> _mergeFromCloud({
    required String? cloudUsageDate,
    required int cloudTempPremiumUnlocksToday,
    required int cloudStaminaAdsToday,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    if (cloudUsageDate == null || cloudUsageDate != _todayKey()) return;

    final localTemp = prefs.getInt("tempPremiumUnlocksToday") ?? 0;
    final localStamina = prefs.getInt("staminaAdsToday") ?? 0;

    await prefs.setInt(
      "tempPremiumUnlocksToday",
      cloudTempPremiumUnlocksToday > localTemp
          ? cloudTempPremiumUnlocksToday
          : localTemp,
    );
    await prefs.setInt(
      "staminaAdsToday",
      cloudStaminaAdsToday > localStamina ? cloudStaminaAdsToday : localStamina,
    );
  }
}
