import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'leaderboard_repository.dart';
import 'player_service.dart';
import 'stamina_service.dart';
import 'usage_limit_service.dart';

/// Outcome of a [PlayerRepository.restorePlayerFromCloud] attempt.
enum RestoreOutcome {
  /// Cloud data was found and applied to the local profile.
  restored,

  /// No cloud data exists for this account (no doc at all, or a doc that
  /// was only ever written to by something other than [syncCurrentPlayer]
  /// -- see the `totalXp`-key check below). This is a genuinely new
  /// account as far as this repository is concerned; it's safe to
  /// proceed and eventually push this device's own local state up.
  nothingToRestore,

  /// The fetch itself failed -- offline, a Firestore hiccup, a
  /// permission error. Unlike [nothingToRestore], we genuinely don't
  /// know whether this account has real cloud data or not, so this
  /// blocks [syncCurrentPlayer] for this uid (see [hasPendingRestore])
  /// until a restore actually succeeds -- a transient failure here must
  /// never be allowed to result in a blank local profile silently
  /// overwriting real cloud history.
  failed,
}

/// Mirrors the player's local profile stats (SharedPreferences, via
/// [PlayerService] -- still the source of truth on the device that's
/// actively being played on) up to their Firestore user document, so
/// progress survives a lost phone, a cleared/reinstalled app, or a second
/// device -- and so a real synced leaderboard has real data to read from.
///
/// Local always wins *while a device already has data for this account*.
/// [restorePlayerFromCloud] is the one path that pulls cloud data back
/// down, and it's only ever called right after [AuthService.linkWithGoogle]
/// resolves to a *pre-existing* account (see
/// [GoogleLinkResult.switchedAccount]) -- that's the only moment a real
/// identity (not just an anonymous session) has proven which cloud history
/// belongs to whoever is sitting in front of the device right now.
class PlayerRepository {
  static final _db = FirebaseFirestore.instance;

  // Persisted (survives app restart) uid for which a restore attempt is
  // known to have failed and hasn't succeeded since -- see
  // restorePlayerFromCloud's `failed` case and syncCurrentPlayer's guard
  // below. Without persisting this, a failed restore would only be
  // remembered for the rest of this app session: the very next launch
  // would call syncCurrentPlayer() from splash_screen with no memory of
  // the failure, and push a blank local profile over the real one.
  static const _pendingRestoreKey = 'restorePendingForUid';

  static Future<void> _setPendingRestoreUid(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingRestoreKey, uid);
  }

  // Only clears the flag if it's still pointing at THIS uid. Without that
  // check, a stale pending flag for one account could be silently dropped
  // by a restore that resolved for a completely different account -- not
  // reachable today (there's no sign-out/switch-account flow yet, so a
  // device only ever goes anonymous -> linked once), but auth_service.dart
  // already contemplates a non-anonymous account later signing into a
  // *different* Google account, and this keeps the guard correctly
  // uid-scoped on both the read and write side once that's possible.
  static Future<void> _clearPendingRestoreUidIfMatches(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_pendingRestoreKey) == uid) {
      await prefs.remove(_pendingRestoreKey);
    }
  }

  static Future<bool> _isRestorePendingFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingRestoreKey) == uid;
  }

  /// Applies the Google-link "finishing touches" that should happen
  /// exactly once a linked account's cloud state is confirmed caught up
  /// (a [RestoreOutcome.restored] or [RestoreOutcome.nothingToRestore]
  /// result) -- auto-filling the display name from Google (only ever over
  /// a placeholder guest name) and granting the one-time sign-in bonus.
  ///
  /// Deliberately takes no BuildContext and shows no UI: this needs to run
  /// from anywhere a restore can complete, including silently in the
  /// background with no screen open at all (splash_screen.dart's startup
  /// retry). Without a call site here too, a restore that failed once and
  /// only succeeded on a later app launch would permanently skip both the
  /// autofill and the bonus, since the original link flow (handleLinkGoogle
  /// / _handleSubscribe) already moved on. Safe to call any number of
  /// times from any number of places -- both steps are individually
  /// guarded against repeating (see PlayerService.hasCustomUsername and
  /// PlayerService.claimGoogleSignInBonusIfNeeded).
  static Future<void> applyPostLinkSetupIfNeeded() async {
    if (!PlayerService.hasCustomUsername) {
      final googleName = AuthService.linkedGoogleDisplayName;
      if (googleName != null && googleName.trim().isNotEmpty) {
        await PlayerService.setUsername(googleName.trim());
      }
    }
    await PlayerService.claimGoogleSignInBonusIfNeeded();
  }

  /// True if a restore for the currently signed-in account is known to
  /// have failed and hasn't succeeded since -- [syncCurrentPlayer] is
  /// refusing to push local data up until it does. Callers that get a
  /// chance to retry (e.g. a screen reopening while still signed in)
  /// should check this and call [restorePlayerFromCloud] again.
  static Future<bool> hasPendingRestore() async {
    final uid = AuthService.uid;
    if (uid == null) return false;
    return _isRestorePendingFor(uid);
  }

  /// Pushes the player's current stats to `users/{uid}` in Firestore. Safe
  /// to call often -- e.g. on every app start and after every game result.
  /// Silently does nothing if we're not signed in yet, and never throws --
  /// a failed/offline sync just means the cloud mirror is a little stale
  /// until the next successful call. Never interrupts gameplay.
  static Future<void> syncCurrentPlayer() async {
    final uid = AuthService.uid;
    if (uid == null) return;

    // A restore that's known to have failed (not just "nothing to
    // restore") is still pending for this uid -- refuse to push local
    // data up until it actually succeeds. This runs unconditionally on
    // every app start and after every game, so without this guard a
    // single transient failure right after sign-in would get silently
    // overwritten into the account's real cloud history on the very next
    // call. See restorePlayerFromCloud's `failed` case.
    if (await _isRestorePendingFor(uid)) return;

    try {
      // Stamina and the daily ad-cap counters, gathered up front. Added
      // 2026-09-02 alongside Practice Mode's wrong-question history below
      // -- all three used to reset for free on reinstall once Android Auto
      // Backup (which had been accidentally providing this same
      // protection) was correctly disabled. See StaminaService/
      // UsageLimitService.snapshotForSync and .mergeFromCloud.
      final staminaSnapshot = StaminaService.snapshotForSync();
      final usageSnapshot = await UsageLimitService.snapshotForSync();

      await _db.collection('users').doc(uid).set({
        'username': PlayerService.username,
        'totalXp': PlayerService.totalXp,
        'gamesPlayed': PlayerService.gamesPlayed,
        'totalQuestionsAnswered': PlayerService.totalQuestionsAnswered,
        'correctAnswers': PlayerService.correctAnswers,
        'wrongAnswers': PlayerService.wrongAnswers,
        'rapidFireHighScore': PlayerService.rapidFireHighScore,
        'currentLeague': PlayerService.getLeague(),
        'premiumStatus': PlayerService.isPremium,
        // So a restore (see [restorePlayerFromCloud]) can bring this back
        // too -- otherwise the one-time sign-in bonus could be claimed
        // again every time this account is reinstalled and re-linked, since
        // the local-only flag would reset to false on the fresh install.
        'googleSignInBonusClaimed': PlayerService.googleSignInBonusClaimed,
        // So a restore (see [restorePlayerFromCloud]) can bring the
        // rename cooldown back too, not just the stats -- otherwise a
        // player who cleared their data mid-cooldown could immediately
        // rename again right after restoring, defeating the cooldown.
        // UTC -- this is read back on whatever device signs in next,
        // potentially in a different timezone entirely.
        'lastUsernameChangeAt':
            PlayerService.lastUsernameChangeAt?.toUtc().toIso8601String(),
        // Practice Mode's wrong-question history -- was previously only
        // surviving a reinstall by accident, via the Auto Backup bug that
        // was fixed separately. See PlayerService.restoreFromCloud for the
        // merge logic on the way back down.
        'wrongQuestionIds': PlayerService.wrongQuestionIds,
        'wrongQuestionProgress': PlayerService.wrongQuestionProgress,
        // Day-streak -- see PlayerService.restoreFromCloud for how this
        // merges back down (whichever side's lastStreakDateKey is strictly
        // more recent wins currentStreak+lastStreakDateKey together;
        // longestStreak is a plain max either way).
        'currentStreak': PlayerService.currentStreak,
        'longestStreak': PlayerService.longestStreak,
        'lastStreakDateKey': PlayerService.lastStreakDateKey,
        'stamina': staminaSnapshot['stamina'],
        'staminaLastUpdate': staminaSnapshot['staminaLastUpdate'],
        'usageDate': usageSnapshot['usageDate'],
        'tempPremiumUnlocksToday': usageSnapshot['tempPremiumUnlocksToday'],
        'staminaAdsToday': usageSnapshot['staminaAdsToday'],
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Keeps the shared leaderboard entry (a small subset of this same
      // data) up to date at the same time -- see LeaderboardRepository.
      await LeaderboardRepository.syncCurrentEntry();
    } catch (_) {
      // Ignored on purpose -- see comment above.
    }
  }

  /// Pulls this account's most recent cloud snapshot back down and makes
  /// it the local truth -- the counterpart to [syncCurrentPlayer]. Only
  /// call this when we're confident the signed-in uid actually is this
  /// player's pre-existing account (e.g. right after
  /// [AuthService.linkWithGoogle] resolves with
  /// [GoogleLinkResult.switchedAccount] true) -- an anonymous account
  /// alone can't prove that, so this must never be called from
  /// anonymous-only sign-in.
  ///
  /// [discardLocalProgress] is forwarded straight to
  /// [PlayerService.restoreFromCloud] -- see its doc comment for exactly
  /// what it changes. Pass true only from the one moment a switch to a
  /// pre-existing account is first confirmed (see
  /// ProfileScreen.handleLinkGoogle); leave it false (the default) for a
  /// retry of a restore that's already pending (see
  /// ProfileScreen._attemptRestore), so real progress made on this same
  /// already-linked account while the first attempt was failing isn't
  /// wiped out by the retry.
  ///
  /// See [RestoreOutcome] for what each result means and what callers
  /// should do about it. A [RestoreOutcome.failed] result also marks this
  /// uid as pending (see [hasPendingRestore]), so [syncCurrentPlayer]
  /// refuses to push local data up until a retry actually succeeds.
  static Future<RestoreOutcome> restorePlayerFromCloud({
    bool discardLocalProgress = false,
  }) async {
    final uid = AuthService.uid;
    if (uid == null) return RestoreOutcome.failed;

    try {
      // Source.server is deliberate, not the default -- a default-source
      // get() that's offline but already has *some* users/{uid} doc in
      // its local cache (e.g. ServerTimeService or EntitlementRepository
      // wrote non-stat fields to it earlier while offline, which lands in
      // the cache immediately) resolves successfully from that cache
      // instead of throwing. That would make the `!totalXp` check below
      // misread "we're offline and can't actually confirm this account
      // has no cloud data" as "nothingToRestore" -- clearing the pending
      // flag and reopening the exact silent-overwrite hole this whole
      // mechanism exists to close. Forcing a server round trip means any
      // offline/unreachable case throws instead and is correctly treated
      // as `failed` below.
      // Also time-bounded, same reasoning as ServerTimeService.sync():
      // Source.server means this can no longer return instantly from a
      // local cache, so on a network that's connected but can't actually
      // reach Firestore (captive portal, dead cellular data, a backend
      // hiccup) the SDK can sit in its connect/backoff cycle for well over
      // 10 seconds before finally throwing UNAVAILABLE on its own. This is
      // awaited on the splash screen's startup path (and by Profile/
      // Premium's own retry attempts), so left unbounded it would just
      // move the exact hang Source.server was fixing to open up
      // somewhere else. A timeout here is handled identically to any
      // other failure -- caught below, pending flag stays set, safe.
      final doc = await _db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 8));
      final data = doc.data();

      // A `users/{uid}` doc can exist with no stat fields at all -- both
      // ServerTimeService and EntitlementRepository write to this same
      // document (for unrelated fields) with merge:true, so it's
      // possible to reach here for a doc that's never actually been
      // through syncCurrentPlayer(). Treat "no doc" and "no totalXp key"
      // the same way: nothing usable to restore, but also nothing to be
      // worried about losing -- this is a genuinely new account as far
      // as this repository is concerned. This is now safe to conclude
      // from this read specifically because it's guaranteed to have come
      // from the server, not a possibly-stale local cache (see above).
      if (!doc.exists || data == null || !data.containsKey('totalXp')) {
        await _clearPendingRestoreUidIfMatches(uid);
        return RestoreOutcome.nothingToRestore;
      }

      final storedUsername = data['username'] as String?;
      final lastRenameString = data['lastUsernameChangeAt'] as String?;

      final cloudWrongIds =
          (data['wrongQuestionIds'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final cloudProgressRaw =
          data['wrongQuestionProgress'] as Map<String, dynamic>?;
      final cloudProgress =
          cloudProgressRaw?.map(
            (key, value) => MapEntry(key, (value as num?)?.toInt() ?? 0),
          ) ??
          const <String, int>{};

      await PlayerService.restoreFromCloud(
        username:
            (storedUsername != null && storedUsername.trim().isNotEmpty)
                ? storedUsername
                : PlayerService.username,
        totalXp: (data['totalXp'] as num?)?.toInt() ?? 0,
        gamesPlayed: (data['gamesPlayed'] as num?)?.toInt() ?? 0,
        totalQuestionsAnswered:
            (data['totalQuestionsAnswered'] as num?)?.toInt() ?? 0,
        correctAnswers: (data['correctAnswers'] as num?)?.toInt() ?? 0,
        wrongAnswers: (data['wrongAnswers'] as num?)?.toInt() ?? 0,
        rapidFireHighScore: (data['rapidFireHighScore'] as num?)?.toInt() ?? 0,
        lastUsernameChangeAt:
            lastRenameString != null
                ? DateTime.tryParse(lastRenameString)?.toLocal()
                : null,
        googleSignInBonusClaimed:
            data['googleSignInBonusClaimed'] as bool? ?? false,
        wrongQuestionIds: cloudWrongIds,
        wrongQuestionProgress: cloudProgress,
        currentStreak: (data['currentStreak'] as num?)?.toInt() ?? 0,
        longestStreak: (data['longestStreak'] as num?)?.toInt() ?? 0,
        lastStreakDateKey: data['lastStreakDateKey'] as String?,
        discardLocalProgress: discardLocalProgress,
      );

      // Stamina and the daily ad-cap counters merge separately -- they
      // aren't PlayerService state, and both merge helpers deliberately
      // read/write SharedPreferences directly rather than relying on
      // in-memory caches, so this is safe regardless of whether
      // StaminaService.loadStamina() has run yet on this call path. See
      // StaminaService.mergeFromCloud / UsageLimitService.mergeFromCloud.
      await StaminaService.mergeFromCloud(
        cloudStamina: (data['stamina'] as num?)?.toInt() ?? 0,
        cloudLastUpdate:
            (data['staminaLastUpdate'] as String?) != null
                ? DateTime.tryParse(
                  data['staminaLastUpdate'] as String,
                )?.toLocal()
                : null,
      );
      await UsageLimitService.mergeFromCloud(
        cloudUsageDate: data['usageDate'] as String?,
        cloudTempPremiumUnlocksToday:
            (data['tempPremiumUnlocksToday'] as num?)?.toInt() ?? 0,
        cloudStaminaAdsToday: (data['staminaAdsToday'] as num?)?.toInt() ?? 0,
      );

      await _clearPendingRestoreUidIfMatches(uid);
      return RestoreOutcome.restored;
    } catch (_) {
      // The fetch itself failed -- we genuinely don't know whether this
      // account has real cloud data. Mark it pending rather than let
      // syncCurrentPlayer() potentially overwrite it on the very next
      // call (see the guard there).
      await _setPendingRestoreUid(uid);
      return RestoreOutcome.failed;
    }
  }
}
