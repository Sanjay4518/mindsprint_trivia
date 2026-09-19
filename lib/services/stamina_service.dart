import 'package:shared_preferences/shared_preferences.dart';
import 'player_service.dart';
import 'server_time_service.dart';

class StaminaService {
  static const int maxStamina = 60;

  static int currentStamina = 60;
  static int lastUsedStamina = 0;

  static DateTime? lastUpdateTime;

  /// Serialises every load/save/merge against each other -- same bug class
  /// and same fix as PlayerService's identical `_prefsChain`/`_serialised`
  /// (see that file for the full reasoning). This service has just as many
  /// uncoordinated call sites writing the same two SharedPreferences keys:
  /// HomeScreen's 30-second stamina-regeneration ticker calling
  /// refillStamina(), ModeEntryHelper spending/refunding stamina on mode
  /// entry and ad rewards, and PlayerRepository merging in a cloud restore
  /// -- any two of which can genuinely overlap in real usage. Without this,
  /// a torn interleave could leave "stamina" and "lastUpdate" mutually
  /// inconsistent on disk, which the next load would then use as the
  /// baseline for regeneration math -- either granting free stamina or
  /// losing legitimately-regenerated stamina. Not locking, just queuing --
  /// each call simply runs after whatever's already pending.
  static Future<void> _prefsChain = Future.value();

  static Future<T> _serialised<T>(Future<T> Function() action) {
    final Future<T> result = _prefsChain.then((_) => action());
    _prefsChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static int get visibleStamina {
    if (PlayerService.isPremium) return maxStamina;
    return currentStamina;
  }

  static Future<void> loadStamina() => _serialised(_loadStamina);

  static Future<void> _loadStamina() async {
    final prefs = await SharedPreferences.getInstance();

    currentStamina = prefs.getInt("stamina") ?? maxStamina;

    String? lastTime = prefs.getString("lastUpdate");

    if (lastTime != null) {
      // .toLocal() so this matches ServerTimeService.now()'s local frame.
      // Values written by this version carry a trailing Z (see
      // saveStamina) and parse as an absolute instant; values written by
      // older versions have no zone marker and still parse as local, which
      // is what they meant when they were written. Either way the instant
      // is right -- what's fixed is that new values can no longer be
      // re-interpreted by a later timezone change.
      final parsed = DateTime.tryParse(lastTime)?.toLocal();
      if (parsed != null) {
        lastUpdateTime = parsed;
        refillStamina();
      } else {
        // Corrupt/unparseable stored timestamp -- treat it like "never
        // saved before" instead of throwing. DateTime.parse used to be
        // used here, and a throw this early in app startup (this runs
        // from splash_screen's initializeApp) could hang the whole app on
        // the splash screen. See splash_screen.dart for the matching fix.
        lastUpdateTime = ServerTimeService.now();
        // Calls the unserialised save directly, not the public
        // saveStamina() -- this whole method is already running as the
        // current link in _prefsChain, so awaiting the public (serialised)
        // version here would enqueue behind its own completion and
        // deadlock. See refillStamina()'s doc comment for the one call
        // path in this file that's fine going through the public version.
        await _saveStamina();
      }
    } else {
      lastUpdateTime = ServerTimeService.now();
      await _saveStamina();
    }

    if (PlayerService.isPremium) {
      currentStamina = maxStamina;
      lastUsedStamina = 0;
      await _saveStamina();
    }
  }

  static Future<void> saveStamina() => _serialised(_saveStamina);

  static Future<void> _saveStamina() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt("stamina", currentStamina);
    // .toUtc() before serialising, always. A local DateTime's
    // toIso8601String() emits no zone suffix ("2026-09-04T21:00:00.000"),
    // and DateTime.parse then re-reads it in whatever timezone is active
    // at read time -- so simply changing the device's timezone silently
    // moved this timestamp hours into the past and handed out a full free
    // stamina refill. ServerTimeService can't defend against that: it
    // corrects a wrong *clock*, while this was the stored value itself
    // changing meaning. The trailing Z that toUtc() produces pins the
    // instant permanently.
    await prefs.setString(
      "lastUpdate",
      (lastUpdateTime ?? ServerTimeService.now()).toUtc().toIso8601String(),
    );
  }

  static void refillStamina() {
    if (PlayerService.isPremium) return;
    if (lastUpdateTime == null) return;

    DateTime now = ServerTimeService.now();

    int minutesPassed = now.difference(lastUpdateTime!).inMinutes;
    int staminaToAdd = minutesPassed ~/ 4;

    if (staminaToAdd > 0) {
      currentStamina += staminaToAdd;

      if (currentStamina >= maxStamina) {
        currentStamina = maxStamina;
        // At full, there's nothing left to accrue toward -- start the next
        // interval from now rather than banking leftover minutes that
        // would grant instant stamina the moment the player spends some.
        lastUpdateTime = now;
      } else {
        // Advance only by the time actually converted into stamina, and
        // carry the remainder forward. Setting this to `now` discarded up
        // to 3 minutes of progress on every check -- and since a check
        // runs on every mode entry and every Home refresh, regeneration
        // was measurably slower for a player actively using the app than
        // for one who left it closed, which is backwards. Never lands in
        // the future: staminaToAdd * 4 <= minutesPassed by construction.
        lastUpdateTime = lastUpdateTime!.add(
          Duration(minutes: staminaToAdd * 4),
        );
      }

      saveStamina();
    }
  }

  static Future<void> refreshStamina() async {
    await loadStamina();
  }

  static Future<void> addStamina(int amount) async {
    if (PlayerService.isPremium) return;

    currentStamina += amount;

    if (currentStamina > maxStamina) {
      currentStamina = maxStamina;
    }

    lastUpdateTime = ServerTimeService.now();
    await saveStamina();
  }

  static bool canPlay(int cost) {
    if (PlayerService.isPremium) return true;
    return currentStamina >= cost;
  }

  static Future<void> unlockPremiumStamina() async {
    currentStamina = maxStamina;
    lastUsedStamina = 0;
    lastUpdateTime = ServerTimeService.now();
    await saveStamina();
  }

  static Future<bool> useStamina(int cost) async {
    if (PlayerService.isPremium) {
      lastUsedStamina = 0;
      return true;
    }

    if (currentStamina < cost) return false;

    currentStamina -= cost;
    lastUsedStamina = cost;

    if (currentStamina < 0) {
      currentStamina = 0;
    }

    lastUpdateTime = ServerTimeService.now();
    await saveStamina();
    return true;
  }

  /// Raw snapshot for [PlayerRepository.syncCurrentPlayer] to push to the
  /// cloud -- uses the in-memory values, which is safe because sync always
  /// runs after this device's own local state is already authoritative
  /// (post game-save, post loadStamina, etc.), matching how every other
  /// field PlayerRepository pushes already works.
  static Map<String, dynamic> snapshotForSync() {
    return {
      'stamina': currentStamina,
      // UTC for the same reason as saveStamina -- and doubly so here,
      // since this value can be read back on a different device in a
      // different timezone entirely.
      'staminaLastUpdate': lastUpdateTime?.toUtc().toIso8601String(),
    };
  }

  /// Cloud-restore support (see PlayerRepository.restorePlayerFromCloud) --
  /// merges a cloud snapshot of stamina into the local value. Takes the
  /// max of the two raw stamina counts rather than either overwriting the
  /// other, matching the same "never regress, merge favors the player"
  /// philosophy used for every other counter this app restores from the
  /// cloud (see PlayerService.restoreFromCloud). Stamina isn't purely
  /// monotonic like XP -- it goes up and down during normal play -- but a
  /// small free-to-play resource is exactly the case where erring toward
  /// the player instead of building perfect cross-device stamina
  /// reconciliation is the right trade.
  ///
  /// Deliberately reads and writes SharedPreferences directly rather than
  /// only touching the in-memory static fields: this can run before or
  /// after [loadStamina] depending on the call site (e.g. the splash
  /// screen's silent startup retry vs. Profile's manual retry button), and
  /// relying on call-site ordering to have already populated the in-memory
  /// values would be fragile -- a [loadStamina] that runs afterward would
  /// just silently overwrite this merge again from the un-merged disk
  /// value. Writing straight to disk (and then also updating the
  /// in-memory fields, in case [loadStamina] already ran on this path)
  /// keeps this correct regardless of ordering.
  static Future<void> mergeFromCloud({
    required int cloudStamina,
    required DateTime? cloudLastUpdate,
  }) => _serialised(
    () => _mergeFromCloud(
      cloudStamina: cloudStamina,
      cloudLastUpdate: cloudLastUpdate,
    ),
  );

  static Future<void> _mergeFromCloud({
    required int cloudStamina,
    required DateTime? cloudLastUpdate,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    final localStamina = prefs.getInt("stamina") ?? maxStamina;
    final localLastUpdateString = prefs.getString("lastUpdate");
    final localLastUpdate =
        localLastUpdateString != null
            ? DateTime.tryParse(localLastUpdateString)?.toLocal()
            : null;

    int mergedStamina =
        cloudStamina > localStamina ? cloudStamina : localStamina;
    if (mergedStamina > maxStamina) mergedStamina = maxStamina;

    final mergedLastUpdate =
        (cloudLastUpdate != null &&
                (localLastUpdate == null ||
                    cloudLastUpdate.isAfter(localLastUpdate)))
            ? cloudLastUpdate
            : localLastUpdate;

    // Resolved once and used for BOTH the disk write and the in-memory
    // field below. These used to diverge: disk got the `?? now` fallback
    // while memory got the raw (possibly null) value, and a null
    // lastUpdateTime makes refillStamina() return early -- freezing
    // regeneration for the rest of the session even though disk was fine.
    final resolvedLastUpdate = mergedLastUpdate ?? ServerTimeService.now();

    await prefs.setInt("stamina", mergedStamina);
    await prefs.setString(
      "lastUpdate",
      resolvedLastUpdate.toUtc().toIso8601String(),
    );

    // Also update the in-memory fields in case loadStamina() already ran
    // on this call path -- harmless no-op otherwise, since loadStamina()
    // will read the just-written values straight back from disk.
    currentStamina = mergedStamina;
    lastUpdateTime = resolvedLastUpdate;
  }
}
