import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/league_service.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../services/server_time_service.dart';
import '../services/settings_service.dart';
import '../services/stamina_service.dart';
import '../widgets/google_signin_button.dart';
import '../widgets/league_badge.dart'; // also defines LeagueProgressCard, used below
import '../widgets/rename_username_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool linkingInProgress = false;

  // True while a Google-linked account has cloud history that hasn't
  // actually been pulled down yet -- see PlayerRepository.hasPendingRestore.
  // Drives a persistent banner (see buildPendingRestoreCard) so this state
  // is visible instead of failing silently forever in the background: a
  // permanently-stuck restore (e.g. a genuine server-side problem, not just
  // "offline right now") would otherwise never surface anywhere.
  bool _restorePending = false;
  bool _restoreRetrying = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    await PlayerService.loadPlayer();
    if (!mounted) return;
    setState(() {});

    // If an earlier restore attempt failed (offline, a Firestore hiccup
    // right after sign-in) and hasn't succeeded since, this screen
    // reopening is a good natural moment to quietly retry it -- the
    // player doesn't have to know a retry is even needed. Shares
    // _restoreRetrying with the manual Retry button (see
    // _retryRestorePending) rather than its own flag, so the button is
    // correctly disabled/spinning while this automatic attempt is still
    // running instead of letting the two race each other.
    if (AuthService.isLinkedWithGoogle &&
        await PlayerRepository.hasPendingRestore()) {
      // hasPendingRestore() is a real await (SharedPreferences), and
      // _attemptRestore's first act is a setState -- so backing out of
      // this screen during that gap would throw "setState() called after
      // dispose()". No lint catches a bare setState after an await.
      if (!mounted) return;
      await _attemptRestore(showFailureSnackBar: false);
    }
  }

  Future<void> _retryRestorePending() async {
    await _attemptRestore(showFailureSnackBar: true);
  }

  // Shared by the silent automatic retry (loadProfile, every time this
  // screen opens) and the manual "Retry now" button (see
  // buildPendingRestoreCard) -- both need identical handling of all three
  // RestoreOutcome cases, and running them through one in-flight guard
  // means they can never end up racing each other (see Round 4 review:
  // that race could leave the banner hidden while the pending flag stayed
  // set, silently blocking sync for the rest of the session).
  Future<void> _attemptRestore({required bool showFailureSnackBar}) async {
    if (_restoreRetrying) return;
    if (!mounted) return;
    setState(() {
      _restoreRetrying = true;
      _restorePending = true;
    });

    // discardLocalProgress left at its default (false/merge) -- this is a
    // retry of a restore that already started (see hasPendingRestore), so
    // any local progress since then is real progress on this same
    // already-linked account, not a separate guest identity's data, and
    // deserves to be merged in rather than discarded.
    final outcome = await PlayerRepository.restorePlayerFromCloud();
    if (!mounted) return;
    setState(() => _restoreRetrying = false);

    switch (outcome) {
      case RestoreOutcome.restored:
      case RestoreOutcome.nothingToRestore:
        // Either way, this account's cloud state is now confirmed caught
        // up -- nothing left pending. The very first attempt (right after
        // linking) may have failed before ever reaching the name-autofill/
        // bonus-claim/sync steps that normally follow, so run them now in
        // case they were skipped; both are safe to call even if they
        // somehow already ran (see their own guards). Only call this
        // "already had progress saved" if something was actually restored
        // -- nothingToRestore means this account genuinely has no cloud
        // history yet, so that phrasing would be misleading.
        setState(() => _restorePending = false);
        await _finishLinkSetup(
          switchedAccount: outcome == RestoreOutcome.restored,
          announce: showFailureSnackBar,
        );
        break;
      case RestoreOutcome.failed:
        // Leave _restorePending true -- the banner is the ongoing
        // indicator. Only the manual retry gets a snackbar too; the
        // silent background attempt (loadProfile, every time this screen
        // opens) staying quiet on failure is deliberate, since the banner
        // already says so and repeating it every time would be noisy.
        if (showFailureSnackBar) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Still couldn't restore your progress -- check your "
                "connection and try again in a moment.",
              ),
            ),
          );
        }
        break;
    }
  }

  // Runs everything that should happen exactly once a Google-linked
  // account is confirmed caught up with its real cloud history -- whether
  // that happened immediately in handleLinkGoogle, or later via a silent
  // background retry or the manual Retry button (see _attemptRestore)
  // after the first attempt failed. Safe to call more than once: the
  // username autofill only ever applies over a placeholder name, and
  // PlayerService.claimGoogleSignInBonusIfNeeded is itself guarded against
  // a repeat claim. [announce] controls only the confirmation snackbar at
  // the end -- the silent background path (loadProfile) passes false so a
  // catch-up that happens to land while this screen isn't the one the
  // player is watching doesn't surprise them with a snackbar; the setup
  // steps themselves always run regardless.
  Future<void> _finishLinkSetup({
    required bool switchedAccount,
    bool announce = true,
  }) async {
    final bonusAlreadyClaimed = PlayerService.googleSignInBonusClaimed;
    await PlayerRepository.applyPostLinkSetupIfNeeded();
    if (mounted) setState(() {});

    unawaited(PlayerRepository.syncCurrentPlayer());
    if (!announce) return;
    if (!mounted) return;

    final baseMessage =
        switchedAccount
            ? "Signed in! This Google account already had progress saved -- you're now using that account."
            : "Google account linked! Your progress is now backed up.";
    final bonusMessage =
        bonusAlreadyClaimed
            ? ""
            : " Here's 20 minutes of free Premium as a thank-you.";

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("$baseMessage$bonusMessage")));
  }

  Future<void> handleLinkGoogle() async {
    setState(() => linkingInProgress = true);
    final result = await AuthService.linkWithGoogle();
    if (!mounted) return;
    setState(() => linkingInProgress = false);

    if (result.ok) {
      // If this Google account already had a MindSprint history under a
      // different install (app data was cleared and reinstalled, or this
      // is a second device), bring that history back down first --
      // otherwise the steps below would treat this as a brand new player
      // and overwrite what's actually still saved in the cloud.
      if (result.switchedAccount) {
        // discardLocalProgress: true -- this is the one moment a switch to
        // a pre-existing account is first confirmed, so whatever guest
        // progress happened on this device right up until now is
        // deliberately dropped in favor of the account's real history. See
        // PlayerService.restoreFromCloud's doc comment for the full
        // reasoning and the bug this fixes.
        final outcome = await PlayerRepository.restorePlayerFromCloud(
          discardLocalProgress: true,
        );
        if (!mounted) return;

        if (outcome == RestoreOutcome.failed) {
          // We know this is a pre-existing account (Firebase itself told
          // us so via switchedAccount), but couldn't actually read its
          // cloud data back down just now -- offline, a Firestore hiccup
          // right after sign-in, etc. Stop here instead of falling
          // through to the autofill/sync below: doing that would push
          // this device's blank/local-only profile over the account's
          // real saved progress. There's no separate "sign in again"
          // action to send the player to -- the sign-in button is already
          // hidden now that they're linked -- so this keeps retrying
          // automatically (loadProfile, every app start) and the banner
          // below (see build()) gives them a manual Retry too.
          setState(() => _restorePending = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Signed in, but couldn't restore your saved progress yet "
                "-- check your connection. We'll keep retrying "
                "automatically, or tap Retry below.",
              ),
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
      }

      await _finishLinkSetup(switchedAccount: result.switchedAccount);
    } else if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          duration: const Duration(seconds: 6),
        ),
      );
    }
    // Cancelled: no snackbar needed, the player just backed out.
  }

  Future<void> handleEditName() async {
    if (!PlayerService.canRenameUsernameNow) {
      final unlockAt = PlayerService.nextUsernameChangeAllowedAt!;
      final daysLeft = unlockAt.difference(ServerTimeService.now()).inDays + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "You can rename again in $daysLeft ${daysLeft == 1 ? "day" : "days"}.",
          ),
        ),
      );
      return;
    }

    final renamed = await showRenameUsernameDialog(context);
    if (renamed == true && mounted) {
      // RenameUsernameDialog already triggers the Firestore sync itself --
      // just refresh this screen's own display of the new name.
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Player ID updated!")));
    }
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget statTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.20),
            const Color(0xFF181C24),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildAvatar() {
    final linked = AuthService.isLinkedWithGoogle;
    final photoUrl = AuthService.linkedGooglePhotoUrl;

    if (linked && photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 34,
        backgroundColor: const Color(0xFF232A36),
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    // Guests (or a linked account with no photo) get a plain generic
    // avatar -- no league medal here anymore, that lives in the League
    // Progress card below instead of being duplicated.
    return const CircleAvatar(
      radius: 34,
      backgroundColor: Color(0xFF232A36),
      child: Icon(Icons.person_rounded, size: 38, color: Colors.white54),
    );
  }

  Widget buildHeader() {
    final progress = LeagueService.progressForXp(PlayerService.totalXp);
    final league = progress.currentLeague;
    final linked = AuthService.isLinkedWithGoogle;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: league.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          buildAvatar(),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        PlayerService.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: handleEditName,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.edit_rounded,
                            size: 18,
                            color: Color(0xFFC084FC),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      linked ? Icons.verified_rounded : Icons.person_outline_rounded,
                      size: 14,
                      color: linked ? Colors.greenAccent : Colors.white38,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      linked ? "Signed in with Google" : "Playing as Guest",
                      style: TextStyle(
                        color: linked ? Colors.greenAccent : Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Only ever shown for guests -- see build() below. Once a player links,
  // the header's compact "Signed in with Google" badge covers this, so
  // there's no linked-state version of this card anymore.
  Widget buildAccountCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_off_rounded, color: Colors.white38, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Playing as Guest",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Your progress is only saved on this device right now. Link a "
            "Google account so you never lose it -- even if you switch "
            "phones."
            "${PlayerService.googleSignInBonusClaimed ? "" : " Link now and get 20 minutes of free Premium."}",
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          GoogleSignInButton(
            onPressed: linkingInProgress ? null : handleLinkGoogle,
            loading: linkingInProgress,
          ),
        ],
      ),
    );
  }

  // Shown whenever this account is linked to Google but still has cloud
  // history that hasn't been pulled down yet (see _restorePending) -- makes
  // an otherwise-invisible background retry loop visible, and gives the
  // player a manual way to try again right now instead of just waiting.
  Widget buildPendingRestoreCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.cloud_sync_rounded, color: Colors.amber, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Still restoring your saved progress",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "We couldn't pull down your account's saved progress yet "
                  "-- check your connection. Your stats shown here may be "
                  "out of date until this finishes.",
                  style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 34,
                  child: OutlinedButton(
                    onPressed: _restoreRetrying ? null : _retryRestorePending,
                    child:
                        _restoreRetrying
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text("Retry now"),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Real, unique, self-chosen Player IDs -- see UsernameRepository and
  // RenameUsernameDialog. The pencil icon next to the name in buildHeader()
  // opens the rename dialog; this card just explains the current state
  // (when the player can rename next).
  Widget buildPlayerIdInfoCard() {
    final canRenameNow = PlayerService.canRenameUsernameNow;
    String subtitle;
    if (canRenameNow) {
      subtitle =
          "Tap the pencil next to your name above to choose a unique "
          "Player ID. Your first change is free, then there's a "
          "${PlayerService.usernameRenameCooldownDays}-day wait between "
          "renames.";
    } else {
      final unlockAt = PlayerService.nextUsernameChangeAllowedAt!;
      final daysLeft =
          unlockAt.difference(ServerTimeService.now()).inDays + 1;
      subtitle =
          "You can rename again in $daysLeft "
          "${daysLeft == 1 ? "day" : "days"}.";
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            canRenameNow ? Icons.badge_rounded : Icons.lock_clock_rounded,
            color: Colors.white38,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PlayerService.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Immediately re-syncs the leaderboard entry so the change (photo shown
  // or removed) is visible to other players right away, rather than
  // waiting for the next natural sync point (app start, a finished round,
  // etc.) -- see LeaderboardRepository.syncCurrentEntry for how the actual
  // add/remove happens.
  Future<void> toggleShowPhotoOnLeaderboard(bool value) async {
    await SettingsService.setShowPhotoOnLeaderboard(value);
    if (!mounted) return;
    setState(() {});
    unawaited(PlayerRepository.syncCurrentPlayer());
  }

  // Only ever shown for linked accounts -- see build() below. Guests have
  // no Google photo to show, so the toggle would have nothing to do.
  Widget buildLeaderboardPhotoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Material(
        color: Colors.transparent,
        child: SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: Colors.amber,
          title: const Text(
            "Show my photo on the leaderboard",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          subtitle: const Text(
            "Off by default. When on, your Google account photo is shown "
            "to every other player who opens the leaderboard, in place of "
            "your league badge.",
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4),
          ),
          value: SettingsService.showPhotoOnLeaderboard,
          onChanged: toggleShowPhotoOnLeaderboard,
        ),
      ),
    );
  }

  Future<void> togglePremiumDebug(bool value) async {
    await PlayerService.setPremium(value);
    if (value) {
      await StaminaService.unlockPremiumStamina();
    } else {
      // Also clear any active temporary Premium window (ad-watch or
      // sign-in bonus) -- otherwise flipping this off can look broken if
      // one happens to still be running, since PlayerService.isPremium
      // stays true until that window actually expires.
      await PlayerService.clearTemporaryPremium();
      await StaminaService.refreshStamina();
    }
    if (!mounted) return;
    setState(() {});
  }

  Widget buildDebugPanel() {
    // Debug-only testing aid. Wrapped in kDebugMode so it is compiled out of
    // release builds automatically -- nothing to remember to remove later.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "DEBUG ONLY – hidden in release builds",
            style: TextStyle(
              color: Colors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          // Wrapped in a transparent Material -- SwitchListTile needs a
          // Material ancestor of its own to paint its background/ink
          // splashes correctly; without one Flutter logs a (harmless but
          // noisy) "ListTile background color or ink splashes may be
          // invisible" exception.
          Material(
            color: Colors.transparent,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Colors.amber,
              title: const Text(
                "Premium (test toggle)",
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                "Flip to test free vs premium behavior without clearing app data.",
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              value: PlayerService.isPremium,
              onChanged: togglePremiumDebug,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = LeagueService.progressForXp(PlayerService.totalXp);

    return Scaffold(
      appBar: AppBar(title: const Text("Player Dashboard")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildHeader(),
              // Once linked, the header's compact "Signed in with Google"
              // badge already says everything this card would -- only show
              // the full card (with the actual sign-in button) for guests
              // who still need to take that action.
              if (!AuthService.isLinkedWithGoogle) ...[
                const SizedBox(height: 16),
                buildAccountCard(),
              ],
              if (_restorePending) ...[
                const SizedBox(height: 16),
                buildPendingRestoreCard(),
              ],
              const SizedBox(height: 16),
              LeagueProgressCard(
                currentLeague: progress.currentLeague,
                nextLeague: progress.nextLeague,
                progress: progress.progress,
                xpToNextLeague: progress.xpToNextLeague,
                totalXp: PlayerService.totalXp,
              ),
              const SizedBox(height: 20),
              sectionTitle("Performance"),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  statTile(
                    title: "Games Played",
                    value: "${PlayerService.gamesPlayed}",
                    icon: Icons.sports_esports_rounded,
                    color: Colors.greenAccent,
                  ),
                  statTile(
                    title: "Accuracy",
                    value:
                        "${PlayerService.accuracyPercentage.toStringAsFixed(1)}%",
                    icon: Icons.track_changes_rounded,
                    color: Colors.orangeAccent,
                  ),
                  statTile(
                    title: "Questions",
                    value: "${PlayerService.totalQuestionsAnswered}",
                    icon: Icons.quiz_rounded,
                    color: Colors.lightBlueAccent,
                  ),
                  statTile(
                    title: "Rapid High Score",
                    value: "${PlayerService.rapidFireHighScore}",
                    icon: Icons.flash_on_rounded,
                    color: Colors.pinkAccent,
                  ),
                  statTile(
                    title: "Best Streak",
                    value:
                        "${PlayerService.longestStreak} day${PlayerService.longestStreak == 1 ? '' : 's'}",
                    icon: Icons.local_fire_department_rounded,
                    color: Colors.deepOrangeAccent,
                  ),
                  statTile(
                    title: "Correct",
                    value: "${PlayerService.correctAnswers}",
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  statTile(
                    title: "Wrong",
                    value: "${PlayerService.wrongAnswers}",
                    icon: Icons.cancel_rounded,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              sectionTitle("Profile"),
              buildPlayerIdInfoCard(),
              if (AuthService.isLinkedWithGoogle) ...[
                const SizedBox(height: 20),
                sectionTitle("Leaderboard"),
                buildLeaderboardPhotoCard(),
              ],
              if (kDebugMode) ...[
                const SizedBox(height: 20),
                sectionTitle("Developer Testing"),
                buildDebugPanel(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
