import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'league_service.dart';
import 'server_time_service.dart';

class PlayerService {
  static String username = "Player";
  static int totalXp = 0;
  static int gamesPlayed = 0;
  static int totalQuestionsAnswered = 0;
  static int correctAnswers = 0;
  static int wrongAnswers = 0;
  static int rapidFireHighScore = 0;
  static String lastKnownLeague = "Bronze";
  static String? lastPromotionFromLeague;
  static String? lastPromotionToLeague;
  static bool _permanentPremium = false;
  static DateTime? _tempPremiumUntil;

  /// Consecutive UTC calendar days the player has played at least one
  /// round on, most recent day included. See [_recordStreakActivity] for
  /// exactly how this advances/resets, and [displayStreak] for what UI
  /// should actually show (this raw field can lag a day behind reality
  /// until the player's next round runs).
  static int currentStreak = 0;

  /// The best [currentStreak] this player has ever reached -- a lifetime
  /// record, never decreases.
  static int longestStreak = 0;

  /// UTC date key (`"yyyy-mm-dd"`, see [_todayStreakKey]) of the last day
  /// that counted toward [currentStreak] -- null if the player has never
  /// played a round yet. Kept private; [hasPlayedToday]/[isStreakAtRisk]
  /// are the derived facts callers actually need.
  static String? _lastStreakDateKey;

  /// Exposed read-only so [PlayerRepository] can include it in the cloud
  /// sync payload (see [restoreFromCloud] for how it's merged back down).
  static String? get lastStreakDateKey => _lastStreakDateKey;

  /// True once the player has already played a round today (UTC), i.e.
  /// today is already counted toward [currentStreak].
  static bool get hasPlayedToday => _lastStreakDateKey == _todayStreakKey();

  /// True when [currentStreak] was last extended yesterday (not today) --
  /// still alive, but will reset to 0 the next time a round is recorded
  /// unless the player plays again before the next UTC day boundary.
  static bool get isStreakAtRisk =>
      currentStreak > 0 && _lastStreakDateKey == _yesterdayStreakKey();

  /// The streak value UI should actually show. [currentStreak] itself only
  /// gets reset to 0 (or restarted at 1) the next time
  /// [recordNormalResult]/[recordRapidFireResult] runs -- so a player who
  /// stops playing for a week would otherwise still see their old streak
  /// number frozen on screen indefinitely. This reads as already-broken
  /// (0) once more than one full UTC day has passed with no play, without
  /// needing a background job to actually zero the stored counter.
  static int get displayStreak {
    if (currentStreak == 0) return 0;
    return (hasPlayedToday || isStreakAtRisk) ? currentStreak : 0;
  }

  /// When the player last used the real self-chosen rename feature (see
  /// [applyUsernameChange]) -- null if they never have, in which case their
  /// first rename is free at any time. Deliberately NOT touched by
  /// [setUsername], so linking a Google account (which auto-fills the
  /// player's real name) never starts or resets this cooldown -- only a
  /// deliberate manual rename does.
  static DateTime? _lastUsernameChangeAt;

  /// Minimum/maximum length for a self-chosen username (see
  /// [validateUsernameFormat]).
  static const int usernameMinLength = 3;
  static const int usernameMaxLength = 20;

  /// How long a player must wait between manual renames, after their first
  /// (free) one. Enforced here on-device only -- see [UsernameRepository]
  /// for why that's an acceptable v1 scope limit for a display name.
  static const int usernameRenameCooldownDays = 30;

  /// True when the player has a real, currently-active Premium
  /// subscription purchased through Google Play Billing (as opposed to
  /// [_permanentPremium], the old debug/manual flag, or a temporary
  /// ad-watch window). Kept in sync by [EntitlementRepository], which
  /// re-checks this against Play Store itself, not just a value cached
  /// from whenever the subscription was first bought.
  static bool _subscriptionPremiumActive = false;

  /// Question IDs the player has answered wrong at least once, most-recent
  /// mistake last. Backs the local "Practice weak questions" mode -- no
  /// backend needed, this is pure SharedPreferences like everything else
  /// here. A question is removed from this list once the player masters it
  /// inside Practice Mode (see [recordPracticeAnswer]).
  static List<String> wrongQuestionIds = [];

  /// How many separate Practice Mode *sessions* a question has been
  /// answered correctly in, keyed by question ID -- these don't need to be
  /// consecutive attempts, just separate sessions. A wrong answer (in any
  /// session) resets a question's count back to 0. Reaching
  /// [masteryThreshold] removes it from [wrongQuestionIds] for good.
  /// Missing a question again outside Practice Mode (in a normal game)
  /// also resets its progress to 0.
  static Map<String, int> wrongQuestionProgress = {};

  /// Separate correct-session encounters needed to master a question.
  /// Deliberately spread across multiple sessions (not "answer it right
  /// twice right now") so mastery reflects real retention over time, not a
  /// lucky back-to-back guess.
  static const int masteryThreshold = 3;

  /// Practice quiz session size -- how many questions one Practice Mode
  /// quiz pulls from the wrong-answer pool. Deliberately smaller than the
  /// full pool so a session stays quick and questions rotate naturally
  /// rather than being one long grind through everything at once.
  static const int practiceSessionSize = 8;

  /// After a question appears in a practice session, it won't be eligible
  /// to appear again for this many *sessions* (a random value in this
  /// range is picked each time, so the rotation doesn't feel mechanical).
  /// This is what makes a question "come back around" naturally every few
  /// quizzes instead of repeating immediately.
  static const int _cooldownMinSessions = 3;
  static const int _cooldownMaxSessions = 4;

  /// Monotonically increasing count of Practice Mode sessions ever started
  /// on this install. Used purely as a counter to schedule cooldowns
  /// against -- not a real timestamp, so it advances only when the player
  /// actually starts a practice session, which is exactly what "wait a few
  /// sessions" should mean here.
  static int _practiceSessionCounter = 0;

  /// Session number (see [_practiceSessionCounter]) at or after which a
  /// question becomes eligible to be picked into a practice session again.
  /// A question with no entry here has never been in a session yet, so
  /// it's immediately eligible.
  static Map<String, int> _practiceNextEligibleSession = {};

  /// Hard cap so this list can't grow forever on a long-lived install.
  /// Oldest mistakes are dropped first once the cap is hit.
  static const int _maxWrongQuestions = 300;

  /// True if the player has real/permanent Premium, OR is currently inside
  /// a temporary ad-watch Premium window. Every existing Premium check in
  /// the app (stamina, daily limits, category access, etc.) reads this one
  /// flag, so it doesn't need to know the difference.
  static bool get isPremium {
    if (_permanentPremium) return true;
    if (_subscriptionPremiumActive) return true;
    return _tempPremiumUntil != null &&
        ServerTimeService.now().isBefore(_tempPremiumUntil!);
  }

  /// True only when Premium access comes from a real Google Play Billing
  /// subscription (not the debug flag, not a temporary ad-watch window).
  static bool get hasActiveSubscription => _subscriptionPremiumActive;

  /// True only when current Premium access comes from a temporary ad-watch
  /// unlock, not a real/permanent/subscription Premium account.
  static bool get hasTemporaryPremiumActive {
    if (_permanentPremium || _subscriptionPremiumActive) return false;
    return _tempPremiumUntil != null &&
        ServerTimeService.now().isBefore(_tempPremiumUntil!);
  }

  /// Time left on the current temporary Premium window, or null if none is
  /// active right now.
  static Duration? get temporaryPremiumRemaining {
    if (!hasTemporaryPremiumActive) return null;
    return _tempPremiumUntil!.difference(ServerTimeService.now());
  }

  /// When the player will next be allowed to rename themselves again, or
  /// null if they can rename right now (either they've never manually
  /// renamed before, or the cooldown has already passed).
  static DateTime? get nextUsernameChangeAllowedAt {
    if (_lastUsernameChangeAt == null) return null;
    final unlockAt = _lastUsernameChangeAt!.add(
      const Duration(days: usernameRenameCooldownDays),
    );
    return ServerTimeService.now().isBefore(unlockAt) ? unlockAt : null;
  }

  /// True if the player is free to use the rename feature right now.
  static bool get canRenameUsernameNow => nextUsernameChangeAllowedAt == null;

  /// True once the player has deliberately chosen their own name at least
  /// once via the real rename flow ([applyUsernameChange]) -- as opposed to
  /// still carrying the auto-generated "GuestNNNN" placeholder or an
  /// auto-filled Google display name. Used to decide whether linking (or
  /// re-linking) a Google account is allowed to auto-fill the display
  /// name, so that can never silently overwrite a name the player actually
  /// picked (see [setUsername] and [PlayerRepository.restorePlayerFromCloud]).
  static bool get hasCustomUsername => _lastUsernameChangeAt != null;

  /// Raw timestamp of the player's last deliberate rename, or null if they
  /// never have. Exposed read-only so [PlayerRepository] can include it in
  /// the cloud sync payload -- without this, restoring a player's stats
  /// from the cloud (see [restoreFromCloud]) would silently reopen their
  /// rename cooldown early, since the local timestamp is what enforces it.
  static DateTime? get lastUsernameChangeAt => _lastUsernameChangeAt;

  /// Checks [name] against the format rules for a self-chosen username
  /// (length, allowed characters). Returns a short user-facing error message
  /// if invalid, or null if the name is fine to submit for a uniqueness
  /// check. Does NOT check uniqueness -- that's [UsernameRepository]'s job,
  /// since it needs a network round trip this can't do.
  static String? validateUsernameFormat(String name) {
    final trimmed = name.trim();
    if (trimmed.length < usernameMinLength) {
      return "Must be at least $usernameMinLength characters.";
    }
    if (trimmed.length > usernameMaxLength) {
      return "Must be $usernameMaxLength characters or fewer.";
    }
    if (!RegExp(r'^[a-zA-Z0-9 _]+$').hasMatch(trimmed)) {
      return "Only letters, numbers, spaces, and underscores.";
    }
    return null;
  }

  /// Commits a real, deliberate rename: updates the local username, starts
  /// (or restarts) the rename cooldown, and persists both. Callers are
  /// expected to have already reserved [newName] via
  /// [UsernameRepository.claimUsername] before calling this -- this method
  /// only handles the local/UI-facing side of a rename, not the uniqueness
  /// check itself.
  static Future<void> applyUsernameChange(String newName) async {
    username = newName.trim();
    _lastUsernameChangeAt = ServerTimeService.now();
    await savePlayer();
  }

  /// Restores profile fields from a previously-synced cloud snapshot (see
  /// [PlayerRepository.restorePlayerFromCloud]) -- used when a player who
  /// already has cloud history (matched by their linked Google account,
  /// the only identity strong enough to prove it's really them) shows up
  /// on a device with no local data for that history, e.g. after clearing
  /// app data, reinstalling, or linking Google on a second device.
  ///
  /// Deliberately does NOT touch Premium/entitlement fields -- those are
  /// revalidated against Play Billing separately (see
  /// EntitlementRepository), not restored from this local mirror.
  ///
  /// [discardLocalProgress] controls how local (device-only, not-yet-
  /// verified) progress is reconciled against the cloud snapshot:
  ///
  /// - true: the cloud snapshot wins outright, for every field below -- XP,
  ///   games played, correct/wrong counts, and the practice question list
  ///   are all replaced wholesale, not merged. This is what runs the moment
  ///   a player links Google and Firebase confirms the account already has
  ///   real history (see PlayerRepository.restorePlayerFromCloud /
  ///   AuthService.linkWithGoogle's switchedAccount). Any local progress
  ///   made while playing as a guest, right up until that exact moment, is
  ///   deliberately discarded -- that guest identity was never part of this
  ///   account's history, so nothing about it should partially blend in
  ///   just because it happens to be smaller (or even larger) than the
  ///   account's real numbers. This also closes a real bug the old
  ///   max()-per-field merge had: wrongQuestionIds merged as a union while
  ///   every stat merged as a max, so a guest's mistakes could land in the
  ///   practice list with no matching wrong answer ever counted in the
  ///   lifetime stats -- mastering all of them later could then push
  ///   correctAnswers past totalQuestionsAnswered, showing an impossible
  ///   over-100% accuracy. A clean wholesale replace can't drift the two
  ///   apart like that, since they always move together.
  ///
  /// - false (default): merges local and cloud instead of replacing --
  ///   every counter takes whichever side is larger, and the practice
  ///   question list/progress are combined. This is for the one legitimate
  ///   case where local progress since the account was already linked
  ///   deserves to be kept: a restore that failed right after linking
  ///   (offline, a Firestore hiccup) and is only catching up on a retry
  ///   later (see ProfileScreen._attemptRestore) -- the player may well
  ///   have kept playing normally on this same, already-linked account in
  ///   the meantime, and that's real progress on the right account, not a
  ///   different identity's data. A wholesale replace here would erase it.
  static Future<void> restoreFromCloud({
    required String username,
    required int totalXp,
    required int gamesPlayed,
    required int totalQuestionsAnswered,
    required int correctAnswers,
    required int wrongAnswers,
    required int rapidFireHighScore,
    DateTime? lastUsernameChangeAt,
    bool googleSignInBonusClaimed = false,
    List<String> wrongQuestionIds = const [],
    Map<String, int> wrongQuestionProgress = const {},
    int currentStreak = 0,
    int longestStreak = 0,
    String? lastStreakDateKey,
    bool discardLocalProgress = false,
  }) async {
    // NOTE: every parameter here deliberately shares its name with the
    // static field it fills, so each assignment below must be qualified
    // with `PlayerService.` -- an unqualified `totalXp = totalXp` would
    // resolve to the parameter on both sides and silently no-op.

    // OR, never AND -- once either side has claimed the one-time Google
    // sign-in bonus, it stays claimed, regardless of which mode this runs
    // in. Without this, the claimed flag (local-only until now) would
    // reset to false on a fresh install even though the account restoring
    // here already has real cloud history, letting the same account claim
    // another free 20 minutes of Premium every time it's uninstalled,
    // reinstalled, and re-linked.
    _googleSignInBonusClaimed =
        _googleSignInBonusClaimed || googleSignInBonusClaimed;

    if (discardLocalProgress) {
      // Cloud wins outright -- see the doc comment above. No comparison,
      // no merge, so the stats and the practice list can never drift out
      // of sync with each other the way the old per-field merge could.
      PlayerService.username = username;
      _lastUsernameChangeAt = lastUsernameChangeAt;

      PlayerService.totalXp = totalXp;
      PlayerService.gamesPlayed = gamesPlayed;
      PlayerService.totalQuestionsAnswered = totalQuestionsAnswered;
      PlayerService.correctAnswers = correctAnswers;
      PlayerService.wrongAnswers = wrongAnswers;
      PlayerService.rapidFireHighScore = rapidFireHighScore;

      var newWrongIds = List<String>.from(wrongQuestionIds);
      var newProgress = Map<String, int>.from(wrongQuestionProgress);
      if (newWrongIds.length > _maxWrongQuestions) {
        final dropped = newWrongIds.sublist(
          0,
          newWrongIds.length - _maxWrongQuestions,
        );
        for (final id in dropped) {
          newProgress.remove(id);
          _practiceNextEligibleSession.remove(id);
        }
        newWrongIds = newWrongIds.sublist(
          newWrongIds.length - _maxWrongQuestions,
        );
      }
      PlayerService.wrongQuestionIds = newWrongIds;
      PlayerService.wrongQuestionProgress = newProgress;

      // Cloud wins outright here too, same as everything else in this
      // branch -- a different account's streak chain has no business
      // partially blending with whatever this guest identity happened to
      // rack up.
      PlayerService.currentStreak = currentStreak;
      PlayerService.longestStreak = longestStreak;
      _lastStreakDateKey = lastStreakDateKey;

      // Re-baseline league bookkeeping against the restored XP directly,
      // rather than routing it through _detectPromotion -- this XP isn't
      // newly earned just now, so it shouldn't trigger a promotion
      // celebration the next time a real promotion check runs.
      lastKnownLeague = getLeague();
      lastPromotionFromLeague = null;
      lastPromotionToLeague = null;

      await savePlayer();
      return;
    }

    // Merge path (discardLocalProgress: false) -- see the doc comment
    // above for exactly when/why this runs instead of the wholesale
    // replace above.
    //
    // Every counter below is merged (max of local vs. cloud) rather than
    // blindly overwritten. A restore can now be retried automatically well
    // after this device was first used (see PlayerRepository's persisted
    // pending-restore flag) -- the player may well have kept playing
    // locally, offline, in the meantime. A blind overwrite from a cloud
    // snapshot taken before that play would silently erase it. Taking the
    // max of each counter can't make either side's number smaller, so at
    // worst this is a no-op for whichever side is already ahead.
    // Username and the rename cooldown are tied together on purpose --
    // taking the cloud's name while keeping the local cooldown (or vice
    // versa) can strand a player mid-rename: display name reverts to the
    // old one, but the cooldown still reflects the newer rename that got
    // reverted, locking them out of renaming back. Whichever side has the
    // strictly later rename timestamp wins BOTH fields together; if
    // neither side has ever done a custom rename (both null), the
    // passed-in username still applies -- it may just be a synced Google
    // display-name default rather than an actual pick, and there's no
    // cooldown either way to disagree about.
    final localLastRename = _lastUsernameChangeAt;
    final cloudIsNewerRename =
        lastUsernameChangeAt != null &&
        (localLastRename == null ||
            lastUsernameChangeAt.isAfter(localLastRename));
    if (cloudIsNewerRename || localLastRename == null) {
      PlayerService.username = username;
      _lastUsernameChangeAt = lastUsernameChangeAt;
    }
    // else: local has a strictly later custom rename than this cloud
    // snapshot -- keep both the local name and the local cooldown as-is.

    PlayerService.totalXp =
        totalXp > PlayerService.totalXp ? totalXp : PlayerService.totalXp;
    PlayerService.gamesPlayed =
        gamesPlayed > PlayerService.gamesPlayed
            ? gamesPlayed
            : PlayerService.gamesPlayed;
    PlayerService.totalQuestionsAnswered =
        totalQuestionsAnswered > PlayerService.totalQuestionsAnswered
            ? totalQuestionsAnswered
            : PlayerService.totalQuestionsAnswered;
    PlayerService.correctAnswers =
        correctAnswers > PlayerService.correctAnswers
            ? correctAnswers
            : PlayerService.correctAnswers;
    PlayerService.wrongAnswers =
        wrongAnswers > PlayerService.wrongAnswers
            ? wrongAnswers
            : PlayerService.wrongAnswers;
    PlayerService.rapidFireHighScore =
        rapidFireHighScore > PlayerService.rapidFireHighScore
            ? rapidFireHighScore
            : PlayerService.rapidFireHighScore;

    // Practice Mode's wrong-question history, merged rather than
    // overwritten -- same reasoning as every counter above. Was previously
    // masked by Android Auto Backup accidentally restoring the whole local
    // profile on reinstall; now that Auto Backup is correctly disabled,
    // this cloud merge is what actually keeps a player's practice history
    // across a reinstall.
    //
    // IDs: union of both sides, preserving this device's existing order
    // and appending any cloud-only IDs after (order here is "most-recent-
    // mistake-last" per the field's own doc comment -- an exact merge of
    // two devices' real chronological order isn't reconstructable from
    // just two ID lists, so this is a reasonable approximation, not a
    // precise interleave).
    final mergedWrongIds = List<String>.from(PlayerService.wrongQuestionIds);
    for (final id in wrongQuestionIds) {
      if (!mergedWrongIds.contains(id)) mergedWrongIds.add(id);
    }

    // Progress: max of each side per question ID -- never regress a
    // player's mastery streak on a question just because this device
    // hadn't seen their progress on another device yet.
    final mergedProgress = Map<String, int>.from(
      PlayerService.wrongQuestionProgress,
    );
    wrongQuestionProgress.forEach((id, cloudValue) {
      final localValue = mergedProgress[id] ?? 0;
      mergedProgress[id] = cloudValue > localValue ? cloudValue : localValue;
    });

    if (mergedWrongIds.length > _maxWrongQuestions) {
      final dropped = mergedWrongIds.sublist(
        0,
        mergedWrongIds.length - _maxWrongQuestions,
      );
      for (final id in dropped) {
        mergedProgress.remove(id);
        _practiceNextEligibleSession.remove(id);
      }
      PlayerService.wrongQuestionIds = mergedWrongIds.sublist(
        mergedWrongIds.length - _maxWrongQuestions,
      );
    } else {
      PlayerService.wrongQuestionIds = mergedWrongIds;
    }
    PlayerService.wrongQuestionProgress = mergedProgress;

    // Streak: mirrors the username/rename-cooldown merge above, not a
    // per-field max -- currentStreak only means anything paired with the
    // exact day chain it was built on, so whichever side's last-played day
    // is strictly more recent wins BOTH fields together (mixing a newer
    // currentStreak with an older lastStreakDateKey, or vice versa, would
    // describe a streak that never actually happened). If both sides last
    // played the same day, or the cloud has no streak data at all (an
    // older snapshot from before this feature existed), local stays as-is.
    // longestStreak is a lifetime record either way, so it alone is a
    // plain max -- safe to take regardless of which day chain wins.
    final localStreakKey = _lastStreakDateKey;
    final cloudStreakIsNewer =
        lastStreakDateKey != null &&
        (localStreakKey == null ||
            lastStreakDateKey.compareTo(localStreakKey) > 0);
    if (cloudStreakIsNewer) {
      PlayerService.currentStreak = currentStreak;
      _lastStreakDateKey = lastStreakDateKey;
    }
    PlayerService.longestStreak =
        longestStreak > PlayerService.longestStreak
            ? longestStreak
            : PlayerService.longestStreak;

    // Re-baseline league bookkeeping against the restored XP directly,
    // rather than routing it through _detectPromotion -- this XP isn't
    // newly earned just now, so it shouldn't trigger a promotion
    // celebration the next time a real promotion check runs.
    lastKnownLeague = getLeague();
    lastPromotionFromLeague = null;
    lastPromotionToLeague = null;

    await savePlayer();
  }

  /// Serialises every [loadPlayer]/[savePlayer] against each other.
  ///
  /// savePlayer() is ~19 separate awaited SharedPreferences writes, and
  /// six different call sites call loadPlayer() with nothing coordinating
  /// them. A load whose reads landed partway through someone else's save
  /// would pull a half-written profile into memory -- new xp, but the old
  /// tempPremiumUntil -- and the next save would then write that mixture
  /// back as truth. The concrete case that motivated this: finishing a
  /// rewarded ad grants temporary Premium and starts a save, the caller
  /// resumes and Home's refresh calls loadPlayer() mid-write, reads the
  /// not-yet-written tempPremiumUntil as absent, and the next save
  /// removes it -- so the player watched the ad, spent one of their daily
  /// unlocks, and got nothing.
  ///
  /// Chaining rather than locking on purpose: each call simply queues
  /// behind whatever is already running. Nothing here calls loadPlayer()
  /// from inside savePlayer() or vice versa, so this cannot deadlock.
  static Future<void> _prefsChain = Future.value();

  static Future<T> _serialised<T>(Future<T> Function() action) {
    final Future<T> result = _prefsChain.then((_) => action());
    // The chain must not break on an error, or every later load/save
    // would fail with the same one. Errors still propagate to the caller
    // through `result`.
    _prefsChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<void> loadPlayer() => _serialised(_loadPlayer);

  static Future<void> _loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    String? storedUsername = prefs.getString("username");
    if (storedUsername == null || storedUsername.trim().isEmpty) {
      // First launch on this install -- mint a stable guest name once and
      // persist it, instead of everyone defaulting to the generic "Player".
      storedUsername = _generateGuestUsername();
      await prefs.setString("username", storedUsername);
    }
    username = storedUsername;
    totalXp = prefs.getInt("xp") ?? 0;
    gamesPlayed = prefs.getInt("games") ?? 0;
    totalQuestionsAnswered = prefs.getInt("totalQuestionsAnswered") ?? 0;
    correctAnswers = prefs.getInt("correctAnswers") ?? 0;
    wrongAnswers = prefs.getInt("wrongAnswers") ?? 0;
    rapidFireHighScore = prefs.getInt("rapidFireHighScore") ?? 0;
    lastKnownLeague = prefs.getString("lastKnownLeague") ?? getLeague();
    lastPromotionFromLeague = prefs.getString("lastPromotionFromLeague");
    lastPromotionToLeague = prefs.getString("lastPromotionToLeague");
    currentStreak = prefs.getInt("currentStreak") ?? 0;
    longestStreak = prefs.getInt("longestStreak") ?? 0;
    _lastStreakDateKey = prefs.getString("lastStreakDateKey");
    _permanentPremium = prefs.getBool("premium") ?? false;
    _subscriptionPremiumActive =
        prefs.getBool("subscriptionPremiumActive") ?? false;
    // .toLocal() on both -- see savePlayer() for why these are stored as
    // UTC now. Legacy values written by earlier versions carry no zone
    // marker and still parse as local, which is what they meant.
    final tempUntilString = prefs.getString("tempPremiumUntil");
    _tempPremiumUntil =
        tempUntilString != null
            ? DateTime.tryParse(tempUntilString)?.toLocal()
            : null;
    final lastUsernameChangeString = prefs.getString("lastUsernameChangeAt");
    _lastUsernameChangeAt =
        lastUsernameChangeString != null
            ? DateTime.tryParse(lastUsernameChangeString)?.toLocal()
            : null;
    _googleSignInBonusClaimed =
        prefs.getBool("googleSignInBonusClaimed") ?? false;
    wrongQuestionIds = prefs.getStringList("wrongQuestionIds") ?? [];
    final progressJson = prefs.getString("wrongQuestionProgress");
    if (progressJson != null) {
      try {
        final decoded = json.decode(progressJson) as Map<String, dynamic>;
        wrongQuestionProgress = decoded.map(
          (key, value) => MapEntry(key, value as int),
        );
      } catch (_) {
        wrongQuestionProgress = {};
      }
    } else {
      wrongQuestionProgress = {};
    }
    _practiceSessionCounter = prefs.getInt("practiceSessionCounter") ?? 0;
    final eligibleJson = prefs.getString("practiceNextEligibleSession");
    if (eligibleJson != null) {
      try {
        final decoded = json.decode(eligibleJson) as Map<String, dynamic>;
        _practiceNextEligibleSession = decoded.map(
          (key, value) => MapEntry(key, value as int),
        );
      } catch (_) {
        _practiceNextEligibleSession = {};
      }
    } else {
      _practiceNextEligibleSession = {};
    }
  }

  /// Queued behind any other in-flight load/save -- see [_serialised].
  static Future<void> savePlayer() => _serialised(_savePlayer);

  static Future<void> _savePlayer() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("username", username);
    await prefs.setInt("xp", totalXp);
    await prefs.setInt("games", gamesPlayed);
    await prefs.setInt("totalQuestionsAnswered", totalQuestionsAnswered);
    await prefs.setInt("correctAnswers", correctAnswers);
    await prefs.setInt("wrongAnswers", wrongAnswers);
    await prefs.setInt("rapidFireHighScore", rapidFireHighScore);
    await prefs.setString("lastKnownLeague", lastKnownLeague);
    if (lastPromotionFromLeague == null || lastPromotionToLeague == null) {
      await prefs.remove("lastPromotionFromLeague");
      await prefs.remove("lastPromotionToLeague");
    } else {
      await prefs.setString(
        "lastPromotionFromLeague",
        lastPromotionFromLeague!,
      );
      await prefs.setString("lastPromotionToLeague", lastPromotionToLeague!);
    }
    await prefs.setInt("currentStreak", currentStreak);
    await prefs.setInt("longestStreak", longestStreak);
    if (_lastStreakDateKey == null) {
      await prefs.remove("lastStreakDateKey");
    } else {
      await prefs.setString("lastStreakDateKey", _lastStreakDateKey!);
    }
    await prefs.setBool("premium", _permanentPremium);
    await prefs.setBool(
      "subscriptionPremiumActive",
      _subscriptionPremiumActive,
    );
    // Both stored as UTC (trailing Z), never as a bare local wall-clock
    // string -- see StaminaService.saveStamina for the full reasoning.
    // Short version: a local-time string with no zone suffix gets
    // re-interpreted in whatever timezone is active when it's read back,
    // so switching the device's timezone used to shift these. Westward
    // for tempPremiumUntil meant hours of extra free Premium.
    if (_tempPremiumUntil == null) {
      await prefs.remove("tempPremiumUntil");
    } else {
      await prefs.setString(
        "tempPremiumUntil",
        _tempPremiumUntil!.toUtc().toIso8601String(),
      );
    }
    if (_lastUsernameChangeAt == null) {
      await prefs.remove("lastUsernameChangeAt");
    } else {
      await prefs.setString(
        "lastUsernameChangeAt",
        _lastUsernameChangeAt!.toUtc().toIso8601String(),
      );
    }
    await prefs.setBool("googleSignInBonusClaimed", _googleSignInBonusClaimed);
    await prefs.setStringList("wrongQuestionIds", wrongQuestionIds);
    await prefs.setString(
      "wrongQuestionProgress",
      json.encode(wrongQuestionProgress),
    );
    await prefs.setInt("practiceSessionCounter", _practiceSessionCounter);
    await prefs.setString(
      "practiceNextEligibleSession",
      json.encode(_practiceNextEligibleSession),
    );
  }

  /// "GuestNNNN" with a random 4-digit number. Generated once on first
  /// launch and then persisted, so it stays stable for that install --
  /// this is a local placeholder, not a verified identity. A future
  /// Firebase Auth pass (see project roadmap) is what makes an identity
  /// that actually follows the player across devices.
  static String _generateGuestUsername() {
    final number = 1000 + Random().nextInt(9000);
    return "Guest$number";
  }

  // setUsername() below is intentionally narrow and separate from the real
  // rename system (see applyUsernameChange() above and UsernameRepository):
  // it's only ever called with the display name Google itself reports for
  // the account a player just linked (see AuthService.linkWithGoogle), never
  // with player-typed text -- so there's nothing to validate for uniqueness
  // or abuse, it's just showing their real name instead of a random
  // "GuestNNNN". It deliberately does NOT touch the rename cooldown, so
  // linking Google never uses up or resets a player's manual rename.
  static Future<void> setUsername(String name) async {
    username = name;
    await savePlayer();
  }

  static Future<void> addXp(int xp) async {
    final previousLeague = getLeague();

    totalXp += xp;
    gamesPlayed++;

    _detectPromotion(previousLeague);
    await savePlayer();
  }

  static Future<void> recordNormalResult({
    required int xpEarned,
    required int correct,
    required int wrong,
    List<String> wrongQuestionIds = const [],
  }) async {
    final previousLeague = getLeague();

    totalXp += xpEarned;
    gamesPlayed++;
    correctAnswers += correct;
    wrongAnswers += wrong;
    totalQuestionsAnswered += correct + wrong;
    _addWrongQuestions(wrongQuestionIds);
    _recordStreakActivity();

    _detectPromotion(previousLeague);
    await savePlayer();
  }

  static Future<void> recordRapidFireResult({
    required int xpEarned,
    required int score,
    required int correct,
    required int wrong,
    List<String> wrongQuestionIds = const [],
  }) async {
    final previousLeague = getLeague();

    // Rapid Fire is deliberately high-risk/high-reward -- a net-negative
    // round really does cost XP (and can drop your league), not just fail
    // to add any. The only floor is 0: a terrible round can zero you out,
    // but never push your lifetime total negative.
    totalXp = max(0, totalXp + xpEarned);
    gamesPlayed++;
    correctAnswers += correct;
    wrongAnswers += wrong;
    totalQuestionsAnswered += correct + wrong;
    if (score > rapidFireHighScore) {
      rapidFireHighScore = score;
    }
    _addWrongQuestions(wrongQuestionIds);
    _recordStreakActivity();

    _detectPromotion(previousLeague);
    await savePlayer();
  }

  /// Adds newly-missed question IDs to the practice list, deduping (a
  /// re-missed question just moves to the end, "most recent mistake") and
  /// trimming from the front once [_maxWrongQuestions] is exceeded. Also
  /// resets each question's mastery progress back to 0 -- a fresh mistake
  /// (even outside Practice Mode) means it's not "nearly mastered" anymore.
  static void _addWrongQuestions(List<String> ids) {
    if (ids.isEmpty) return;

    for (final id in ids) {
      wrongQuestionIds.remove(id);
      wrongQuestionIds.add(id);
      wrongQuestionProgress[id] = 0;
    }

    if (wrongQuestionIds.length > _maxWrongQuestions) {
      final dropped = wrongQuestionIds.sublist(
        0,
        wrongQuestionIds.length - _maxWrongQuestions,
      );
      wrongQuestionIds = wrongQuestionIds.sublist(
        wrongQuestionIds.length - _maxWrongQuestions,
      );
      for (final id in dropped) {
        wrongQuestionProgress.remove(id);
        _practiceNextEligibleSession.remove(id);
      }
    }
  }

  /// Starts a new Practice Mode session: advances the session counter, then
  /// randomly draws up to [practiceSessionSize] question IDs from whichever
  /// wrong questions are currently off cooldown (see
  /// [_practiceNextEligibleSession]). Every drawn question -- right or
  /// wrong doesn't matter here -- gets put back on a fresh 3-4 session
  /// cooldown, so it naturally won't reappear again for a few quizzes.
  ///
  /// If cooldowns have somehow made *everything* ineligible (e.g. lots of
  /// practicing in a short burst with a small pool), falls back to ignoring
  /// cooldown for this one session rather than blocking the player from
  /// practicing at all.
  static Future<List<String>> startPracticeSession() async {
    if (wrongQuestionIds.isEmpty) return [];

    _practiceSessionCounter++;

    List<String> eligible =
        wrongQuestionIds.where((id) {
          final nextEligible = _practiceNextEligibleSession[id] ?? 0;
          return nextEligible <= _practiceSessionCounter;
        }).toList();

    if (eligible.isEmpty) {
      eligible = List<String>.from(wrongQuestionIds);
    }

    eligible.shuffle(Random());
    final selected =
        eligible.take(practiceSessionSize).toList(growable: false);

    final random = Random();
    for (final id in selected) {
      final cooldown =
          _cooldownMinSessions +
          random.nextInt(_cooldownMaxSessions - _cooldownMinSessions + 1);
      _practiceNextEligibleSession[id] =
          _practiceSessionCounter + cooldown;
    }

    await savePlayer();
    return selected;
  }

  /// Called from Practice Mode after the player answers a previously-missed
  /// question. A question needs to be answered correctly across
  /// [masteryThreshold] *separate sessions* to be mastered (removed from
  /// the practice list for good, and quietly moved from the lifetime
  /// "wrong" tally into the lifetime "correct" tally -- see
  /// [correctAnswers]/[wrongAnswers] -- so mastering something really does
  /// improve your overall stats). Any wrong answer resets that question's
  /// progress back to 0, even if it already had sessions banked. A wrong
  /// answer during practice does NOT touch lifetime stats -- only real
  /// gameplay and mastery moments do, so practicing never counts against
  /// you. Returns true only on the answer that actually achieves mastery,
  /// so the UI can show a distinct "Mastered!" moment.
  static Future<bool> recordPracticeAnswer(
    String questionId,
    bool correct,
  ) async {
    if (!wrongQuestionIds.contains(questionId)) return false;

    if (!correct) {
      wrongQuestionProgress[questionId] = 0;
      await savePlayer();
      return false;
    }

    final newStreak = (wrongQuestionProgress[questionId] ?? 0) + 1;

    if (newStreak >= masteryThreshold) {
      wrongQuestionIds.remove(questionId);
      wrongQuestionProgress.remove(questionId);
      _practiceNextEligibleSession.remove(questionId);
      wrongAnswers = wrongAnswers > 0 ? wrongAnswers - 1 : 0;
      correctAnswers += 1;
      await savePlayer();
      return true;
    }

    wrongQuestionProgress[questionId] = newStreak;
    await savePlayer();
    return false;
  }

  /// Separate correct-session encounters currently banked toward mastering
  /// this question (0 up to [masteryThreshold] - 1 -- reaching the
  /// threshold removes the question entirely).
  static int correctStreakFor(String questionId) {
    return wrongQuestionProgress[questionId] ?? 0;
  }

  /// `"yyyy-mm-dd"` for a UTC instant -- same zero-padded format as
  /// [UsageLimitService]'s day key, so the two remain simple, correct
  /// lexicographic string comparisons wherever either is compared.
  static String _dateKeyFor(DateTime utc) {
    return "${utc.year}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}";
  }

  /// Today's UTC date key. Deliberately UTC, not the device's local date --
  /// see [UsageLimitService]'s own `_todayKey` for the full reasoning
  /// (short version: a local-date key can be rolled forward for free just
  /// by changing the device's timezone, which would let a player manufacture
  /// streak days that were never actually played on separate calendar
  /// days). [ServerTimeService.now] on top of that closes the matching
  /// hole for a rolled-forward *clock*, not just timezone.
  static String _todayStreakKey() => _dateKeyFor(ServerTimeService.now().toUtc());

  /// UTC date key for the calendar day immediately before [_todayStreakKey].
  /// Subtracting a fixed 24-hour Duration from a UTC instant is exact (UTC
  /// has no DST to trip over), so this always lands on the correct
  /// previous calendar date.
  static String _yesterdayStreakKey() => _dateKeyFor(
    ServerTimeService.now().toUtc().subtract(const Duration(days: 1)),
  );

  /// Advances the day-streak by at most one day per call, based on whether
  /// [_lastStreakDateKey] was today, yesterday, or further back:
  /// - today already: no-op, already counted.
  /// - yesterday: extends the streak by one day.
  /// - anything else (including never played before): starts a fresh
  ///   streak of 1.
  ///
  /// Called once per completed round -- see [recordNormalResult] and
  /// [recordRapidFireResult], the only two places a round is actually
  /// recorded. Deliberately not folded into [addXp], which nothing in the
  /// app currently calls for real gameplay.
  static void _recordStreakActivity() {
    final today = _todayStreakKey();
    if (_lastStreakDateKey == today) return;

    currentStreak = (_lastStreakDateKey == _yesterdayStreakKey())
        ? currentStreak + 1
        : 1;
    if (currentStreak > longestStreak) longestStreak = currentStreak;
    _lastStreakDateKey = today;
  }

  static void _detectPromotion(String previousLeague) {
    final currentLeague = getLeague();
    final previousRank = LeagueService.rankForLeague(previousLeague);
    final currentRank = LeagueService.rankForLeague(currentLeague);

    lastKnownLeague = currentLeague;

    if (currentRank > previousRank) {
      lastPromotionFromLeague = previousLeague;
      lastPromotionToLeague = currentLeague;
    }
    // No `else` clearing lastPromotionFromLeague/lastPromotionToLeague here
    // on purpose. This method only knows about *this* round's before/after
    // league -- it has no way to tell whether an earlier round already left
    // a promotion pending that PromotionCelebrationDialog hasn't shown yet
    // (e.g. the player tapped Play Again fast enough that a second round
    // finished, and didn't itself cross a league boundary, before the first
    // round's celebration dialog ever ran -- see
    // PromotionCelebrationDialog.showIfPending's matching guard). Wiping the
    // fields unconditionally here used to erase that still-pending
    // promotion for good, since this is called from every XP-earning path.
    // A pending promotion is now only ever cleared by actually consuming it
    // (PlayerService.clearRecentPromotion, called by showIfPending right
    // before it displays) or by a genuine cloud re-baseline
    // (restoreFromCloud, which has its own, deliberate reasoning for
    // clearing both fields).
  }

  static bool get hasRecentPromotion =>
      lastPromotionFromLeague != null && lastPromotionToLeague != null;

  /// Consumes a pending promotion so it can't be celebrated twice -- call
  /// this once the celebration UI has actually been shown (see
  /// PromotionCelebrationDialog.showIfPending). Safe to call even when
  /// nothing is pending.
  static Future<void> clearRecentPromotion() async {
    if (!hasRecentPromotion) return;
    lastPromotionFromLeague = null;
    lastPromotionToLeague = null;
    await savePlayer();
  }

  static double get accuracyPercentage {
    if (totalQuestionsAnswered == 0) return 0;
    return (correctAnswers / totalQuestionsAnswered) * 100;
  }

  static Future<void> setPremium(bool value) async {
    _permanentPremium = value;
    await savePlayer();
  }

  /// Set by [EntitlementRepository] whenever it confirms (or revokes) real
  /// Premium access from Google Play Billing. Not meant to be called
  /// directly from UI code.
  static Future<void> setSubscriptionPremiumActive(bool active) async {
    _subscriptionPremiumActive = active;
    await savePlayer();
  }

  /// Grants (or extends) a temporary Premium window earned by watching a
  /// rewarded ad or claiming the Google sign-in bonus. Stacks [duration] on
  /// top of whatever time is already remaining -- watching another ad while
  /// a window is still active always leaves the player at least as well off
  /// as before, never shorter. If no window is currently active (or the
  /// previous one has already expired), this starts a fresh window from
  /// now, same as before.
  static Future<void> grantTemporaryPremium(Duration duration) async {
    final now = ServerTimeService.now();
    final base = (_tempPremiumUntil != null && _tempPremiumUntil!.isAfter(now))
        ? _tempPremiumUntil!
        : now;
    _tempPremiumUntil = base.add(duration);
    await savePlayer();
  }

  /// Ends any active temporary Premium window immediately (ad-watch or
  /// sign-in bonus). Mainly for the debug Premium toggle -- without this,
  /// turning the debug flag off while a temporary window happens to still
  /// be running would leave [isPremium] stuck on true, since it's true if
  /// *either* the permanent flag or a temporary window is active.
  static Future<void> clearTemporaryPremium() async {
    _tempPremiumUntil = null;
    await savePlayer();
  }

  static bool _googleSignInBonusClaimed = false;

  /// True once the player has already claimed their one-time "sign in with
  /// Google" temporary Premium bonus.
  static bool get googleSignInBonusClaimed => _googleSignInBonusClaimed;

  /// Grants a one-time 20-minute temporary Premium bonus the first time a
  /// player links a Google account -- same mechanism as the "watch an ad"
  /// bonus, just earned a different way. Safe to call every time a Google
  /// link succeeds; does nothing if the bonus was already claimed before,
  /// so it can never be farmed by re-triggering the sign-in flow.
  static Future<void> claimGoogleSignInBonusIfNeeded() async {
    if (_googleSignInBonusClaimed) return;
    _googleSignInBonusClaimed = true;
    await grantTemporaryPremium(const Duration(minutes: 20));
  }

  static String getLeague() {
    return LeagueService.leagueForXp(totalXp).name;
  }

  static int getCurrentLeagueMinXp() {
    return LeagueService.leagueForXp(totalXp).minXp;
  }

  static int? getNextLeagueMinXp() {
    return LeagueService.nextLeagueForXp(totalXp)?.minXp;
  }

  static String getNextLeagueName() {
    return LeagueService.nextLeagueForXp(totalXp)?.name ?? "Max League";
  }

  static double getLeagueProgress() {
    return LeagueService.progressForXp(totalXp).progress;
  }

  static int getXpToNextLeague() {
    return LeagueService.progressForXp(totalXp).xpToNextLeague;
  }

  static String getPerformanceBadge(double accuracy) {
    if (accuracy >= 90) return "Elite Performer";
    if (accuracy >= 75) return "Sharp Mind";
    if (accuracy >= 50) return "Getting There";
    return "Needs Improvement";
  }

  static String getPerformanceMessage(double accuracy) {
    if (accuracy >= 90) return "Outstanding performance!";
    if (accuracy >= 75) return "Great job, keep pushing!";
    if (accuracy >= 50) return "Decent effort, improve accuracy.";
    return "Focus and try again.";
  }

  static List<Map<String, dynamic>> getLeaderboardForLeague(String league) {
    final Map<String, List<Map<String, dynamic>>> leaguePlayers = {
      "Bronze": [
        {"name": username, "xp": totalXp, "league": getLeague()},
        {"name": "Player B1", "xp": 420, "league": "Bronze"},
        {"name": "Player B2", "xp": 380, "league": "Bronze"},
        {"name": "Player B3", "xp": 335, "league": "Bronze"},
        {"name": "Player B4", "xp": 290, "league": "Bronze"},
        {"name": "Player B5", "xp": 240, "league": "Bronze"},
        {"name": "Player B6", "xp": 180, "league": "Bronze"},
        {"name": "Player B7", "xp": 130, "league": "Bronze"},
      ],
      "Silver": [
        {"name": "Player S1", "xp": 1450, "league": "Silver"},
        {"name": "Player S2", "xp": 1320, "league": "Silver"},
        {"name": "Player S3", "xp": 1190, "league": "Silver"},
        {"name": "Player S4", "xp": 1050, "league": "Silver"},
        {"name": "Player S5", "xp": 970, "league": "Silver"},
        {"name": "Player S6", "xp": 880, "league": "Silver"},
      ],
      "Gold": [
        {"name": "Player G1", "xp": 2840, "league": "Gold"},
        {"name": "Player G2", "xp": 2490, "league": "Gold"},
        {"name": "Player G3", "xp": 2250, "league": "Gold"},
        {"name": "Player G4", "xp": 1990, "league": "Gold"},
        {"name": "Player G5", "xp": 1720, "league": "Gold"},
      ],
      "Platinum": [
        {"name": "Player P1", "xp": 4700, "league": "Platinum"},
        {"name": "Player P2", "xp": 4380, "league": "Platinum"},
        {"name": "Player P3", "xp": 4010, "league": "Platinum"},
        {"name": "Player P4", "xp": 3520, "league": "Platinum"},
        {"name": "Player P5", "xp": 3200, "league": "Platinum"},
      ],
      "Diamond": [
        {"name": "Player D1", "xp": 8200, "league": "Diamond"},
        {"name": "Player D2", "xp": 7600, "league": "Diamond"},
        {"name": "Player D3", "xp": 7050, "league": "Diamond"},
        {"name": "Player D4", "xp": 6400, "league": "Diamond"},
      ],
      "Master": [
        {"name": "Player M1", "xp": 11600, "league": "Master"},
        {"name": "Player M2", "xp": 10500, "league": "Master"},
        {"name": "Player M3", "xp": 9400, "league": "Master"},
      ],
      "Legend": [
        {"name": "Player L1", "xp": 18400, "league": "Legend"},
        {"name": "Player L2", "xp": 15100, "league": "Legend"},
        {"name": "Player L3", "xp": 12800, "league": "Legend"},
      ],
    };

    final players = List<Map<String, dynamic>>.from(
      leaguePlayers[league] ?? [],
    );

    if (getLeague() == league) {
      final alreadyExists = players.any((p) => p["name"] == username);
      if (!alreadyExists) {
        players.add({"name": username, "xp": totalXp, "league": getLeague()});
      }
    }

    players.sort((a, b) => (b["xp"] as int).compareTo(a["xp"] as int));

    for (int i = 0; i < players.length; i++) {
      players[i]["rank"] = i + 1;
    }

    return players;
  }
}
