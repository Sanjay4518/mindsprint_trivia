import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/mode_entry_helper.dart';
import '../services/auth_service.dart';
import '../services/entitlement_repository.dart';
import '../services/league_service.dart';
import '../services/notification_service.dart';
import '../services/player_service.dart';
import '../services/server_time_service.dart';
import '../services/stamina_service.dart';
import '../services/update_service.dart';
import '../widgets/league_badge.dart';
import '../widgets/stamina_bar.dart';
import 'leaderboard_screen.dart';
import 'practice_mode_screen.dart';
import 'premium_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Live-updates the temporary-Premium countdown on [buildPremiumCard]
  /// every second while a temp window (ad-watch or the Google sign-in
  /// bonus) is running. Only ticks while needed -- see
  /// [_maybeStartPremiumTicker].
  Timer? _premiumTicker;

  /// Live-updates the stamina bar as it regenerates, so "1 stamina every 4
  /// minutes" (the caption StaminaBar itself shows) is actually visible
  /// happening rather than only updating the next time this screen happens
  /// to rebuild (e.g. navigating away and back). Only ticks while it can
  /// matter -- see [_maybeStartStaminaTicker]. A longer interval than the
  /// Premium ticker above on purpose: stamina only changes once every 4
  /// minutes, so there's nothing to gain from checking every second.
  Timer? _staminaTicker;

  // Shown at most once per install -- see _maybeShowFirstLaunchSignInPrompt.
  // A returning player who signs in with Google on the exact same device
  // they'd used before is usually reauthenticated silently by Google Sign-
  // In itself with no guest phase at all; this prompt exists for everyone
  // else -- a new device, a reinstall that lost the cached credential, or
  // someone who just hasn't noticed the sign-in option yet -- so they're
  // asked up front, before they've had a chance to rack up much guest
  // activity that would otherwise just be discarded the moment they do
  // sign in to a pre-existing account (see PlayerService.restoreFromCloud).
  static const _signInNudgeShownKey = 'hasShownFirstLaunchSignInPrompt';

  @override
  void initState() {
    super.initState();
    refreshData();
    unawaited(_maybeShowFirstLaunchSignInPrompt());
    unawaited(_maybeCheckForAppUpdate());
  }

  /// Awaits the same in-app-update check SplashScreen already kicked off
  /// (or starts it fresh, if this is ever the first call -- see
  /// UpdateService's own guard) and, once a flexible update has actually
  /// finished downloading, shows a persistent "Restart to update" snackbar.
  /// Runs unawaited from initState so it never delays showing Home -- the
  /// download this is awaiting can take a while, and gameplay elsewhere is
  /// completely unaffected while it's in progress. Home is the app's one
  /// long-lived root screen (never popped, everything else pushes on top
  /// of it), so `mounted` is effectively always true by the time this
  /// resolves -- the check is still here defensively, same as every other
  /// post-await UI action in this file.
  Future<void> _maybeCheckForAppUpdate() async {
    final bool ready = await UpdateService.checkAndStartFlexibleUpdate();
    if (!ready || !mounted) return;
    _showUpdateReadySnackBar();
  }

  void _showUpdateReadySnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF181C24),
        content: const Text(
          "An update has finished downloading.",
          style: TextStyle(color: Colors.white),
        ),
        // No fixed short duration on purpose -- this needs to stay visible
        // until the player actually acts on it (or dismisses it), not
        // disappear on its own like a normal transient snackbar.
        duration: const Duration(days: 1),
        action: SnackBarAction(
          label: "Restart",
          textColor: const Color(0xFFF7B538),
          onPressed: () => unawaited(UpdateService.completeUpdate()),
        ),
      ),
    );
  }

  Future<void> _maybeShowFirstLaunchSignInPrompt() async {
    if (AuthService.isLinkedWithGoogle) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_signInNudgeShownKey) ?? false) return;
    await prefs.setBool(_signInNudgeShownKey, true);
    if (!mounted) return;
    // Same isCurrent re-check as PromotionCelebrationDialog/
    // SignInProtectPromptDialog, and for the same reason: this method runs
    // unawaited from initState(), across two real awaits (the
    // SharedPreferences read+write above), before showing a dialog. If the
    // player navigates away from Home in that window, `mounted` stays true
    // (HomeScreen is still in the tree, just not on top) but this would
    // otherwise pop the dialog over whatever screen they've since
    // navigated to.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;

    final bool? goToSignIn = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Played MindSprint before?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Sign in with Google to check for progress saved from a "
              "previous install or another phone. If this is your first "
              "time, no worries -- you can keep playing as a guest and "
              "sign in later any time from your Profile.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Not now"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Sign In"),
              ),
            ],
          ),
    );

    if (goToSignIn == true &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? false)) {
      openProfile();
    }
  }

  @override
  void dispose() {
    _premiumTicker?.cancel();
    _staminaTicker?.cancel();
    super.dispose();
  }

  // Both tickers below cancel via the timer handed to their own callback,
  // never via the field. dispose() can only cancel whatever the field
  // happens to hold at that moment, so a timer created after disposal --
  // refreshData() awaits twice before starting them, and Home can be
  // disposed during that gap when a screen returns via
  // pushAndRemoveUntil -- was unreachable and uncancellable, and would
  // then tick forever holding the dead State in memory. Cancelling `t`
  // also avoids an older callback cancelling a newer timer that has since
  // replaced it in the field.
  void _maybeStartPremiumTicker() {
    _premiumTicker?.cancel();
    if (PlayerService.hasTemporaryPremiumActive) {
      _premiumTicker = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        if (!PlayerService.hasTemporaryPremiumActive) {
          t.cancel();
          // Temporary Premium just expired. _maybeStartStaminaTicker never
          // starts a stamina ticker while Premium is active (unlimited
          // stamina), so if Home has been sitting open the whole time
          // (no refreshData() call to re-evaluate it), the stamina bar
          // would otherwise stay visually frozen until the player next
          // leaves and returns to Home. Kicking it here just resumes the
          // on-screen ticking promptly -- StaminaService itself always
          // computes real regeneration from elapsed time regardless of
          // whether this timer is running, so no stamina value is affected
          // either way.
          _maybeStartStaminaTicker();
        }
        setState(() {});
      });
    }
  }

  void _maybeStartStaminaTicker() {
    _staminaTicker?.cancel();
    if (!PlayerService.isPremium &&
        StaminaService.currentStamina < StaminaService.maxStamina) {
      _staminaTicker = Timer.periodic(const Duration(seconds: 30), (t) {
        if (!mounted) {
          t.cancel();
          return;
        }
        StaminaService.refillStamina();
        if (PlayerService.isPremium ||
            StaminaService.currentStamina >= StaminaService.maxStamina) {
          t.cancel();
        }
        setState(() {});
      });
    }
  }

  Future<void> refreshData() async {
    // Fire-and-forget: keeps the device-vs-server clock offset fresh every
    // time Home reloads (i.e. constantly, between every action), so a clock
    // trick has almost no window to slip through. Never awaited so a
    // slow/offline network never delays the Home screen. See
    // ServerTimeService for why this exists.
    unawaited(ServerTimeService.sync());
    // Re-checks real subscription status against Play Store every time
    // Home reloads -- catches a cancelled/expired subscription promptly,
    // and also picks up a purchase made moments ago on the Premium
    // screen. Fire-and-forget so a slow network never delays Home.
    unawaited(EntitlementRepository.refreshEntitlement());
    await PlayerService.loadPlayer();
    await StaminaService.loadStamina();
    // Bail before starting anything if Home went away during those two
    // awaits -- otherwise a timer gets created that dispose() has already
    // run past and can never cancel. See _maybeStartPremiumTicker.
    if (!mounted) return;
    _maybeStartPremiumTicker();
    _maybeStartStaminaTicker();
    setState(() {});

    // Fire-and-forget, after everything above -- both calls fully
    // re-evaluate current stamina/streak state and either (re)schedule or
    // cancel their one reminder to match, so this is safe and cheap to run
    // on every single refreshData() (app open, every mode entry, every
    // screen return). See NotificationService's own doc comment for why
    // this one call site covers every case that matters. Never awaited:
    // scheduling a local notification must never delay Home rendering.
    unawaited(NotificationService.scheduleStaminaFullReminderIfNeeded());
    unawaited(NotificationService.scheduleStreakReminderIfNeeded());
  }

  void openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const ProfileScreen()),
    ).then((_) => refreshData());
  }

  void openLeaderboard() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LeaderboardScreen()),
    ).then((_) => refreshData());
  }

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SettingsScreen()),
    ).then((_) => refreshData());
  }

  void openPremium() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PremiumScreen()),
    ).then((_) => refreshData());
  }

  void openPracticeMode() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PracticeModeScreen()),
    ).then((_) => refreshData());
  }

  /// Practice Mode (reviewing and re-practicing wrong answers) is a Premium
  /// feature -- same "watch ad for temporary unlock, or go Premium" bridge
  /// already used for locked categories, so free players still see a clear
  /// path in rather than a dead end.
  Future<void> _showPracticeLockedPrompt() async {
    final bool? watchAd = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Practice Mode is Premium",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Reviewing and re-practicing the questions you've gotten "
              "wrong is a Premium feature for players who want to seriously "
              "improve. Watch a short ad to unlock it for 15 minutes, or go "
              "Premium for unlimited access.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Not now"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Watch Ad"),
              ),
            ],
          ),
    );

    // Bare `mounted` (the State's own getter) rather than `context.mounted`
    // -- functionally identical for a State's own context, but this is
    // what the analyzer wants to see immediately guarding a `State.context`
    // use across an await (use_build_context_synchronously).
    if (watchAd != true || !mounted) return;

    final bool success = await ModeEntryHelper.tryWatchAdForTemporaryPremium(
      context,
    );

    if (!success) return;

    await refreshData();
    if (!mounted) return;
    openPracticeMode();
  }

  /// The day-streak card -- hidden entirely until the player has an actual
  /// streak going (see [PlayerService.displayStreak], which reads as 0
  /// once a streak has lapsed even before the stored counter is reset), so
  /// a brand-new install never shows a hollow "0 day streak".
  Widget buildStreakCard() {
    final streak = PlayerService.displayStreak;
    if (streak <= 0) return const SizedBox.shrink();

    final String subtitle;
    if (PlayerService.hasPlayedToday) {
      subtitle = "Nice! You've kept the streak alive today.";
    } else if (PlayerService.isStreakAtRisk) {
      subtitle = "Play today to keep your streak going!";
    } else {
      subtitle = "Play daily to build your streak.";
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7A2E0E), Color(0xFFFF7A29)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.deepOrange.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$streak day streak",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildLeagueProgressCard() {
    final progress = LeagueService.progressForXp(PlayerService.totalXp);

    return LeagueProgressCard(
      currentLeague: progress.currentLeague,
      nextLeague: progress.nextLeague,
      progress: progress.progress,
      xpToNextLeague: progress.xpToNextLeague,
      totalXp: PlayerService.totalXp,
      // Leaderboard used to be its own separate button further down the
      // screen -- merged in here instead, right next to the league/XP info
      // it's directly related to, rather than living apart from it.
      onViewLeaderboard: openLeaderboard,
    );
  }

  Widget buildTopAvatar() {
    final linked = AuthService.isLinkedWithGoogle;
    final photoUrl = AuthService.linkedGooglePhotoUrl;

    if (linked && photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 31,
        backgroundColor: Colors.white.withValues(alpha: 0.15),
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: 31,
      backgroundColor: Colors.white.withValues(alpha: 0.15),
      child: const Icon(Icons.person_rounded, size: 34, color: Colors.white),
    );
  }

  Widget buildPremiumCard() {
    if (PlayerService.hasTemporaryPremiumActive) {
      // Temporary Premium (ad-watch or the Google sign-in bonus): unlike
      // real/paid Premium below, this stays tappable -- a player using a
      // temp window should still be able to jump to the real purchase
      // flow -- and shows a live mm:ss countdown of the time left.
      final remaining = PlayerService.temporaryPremiumRemaining;
      final minutes = remaining == null ? 0 : remaining.inMinutes;
      final seconds = remaining == null ? 0 : remaining.inSeconds % 60;
      final countdown =
          "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";

      return InkWell(
        onTap: openPremium,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF164A2D), Color(0xFF1F8F4A)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Temporary Premium Active",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$countdown left • Tap to get unlimited with real Premium",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      );
    }

    if (PlayerService.isPremium) {
      // Real/permanent Premium (subscription or the debug flag). Tappable
      // too -- per Sanjay's feedback (2026-08-20), a subscriber should
      // always be able to reach the Premium screen from Home to see their
      // status / manage the subscription, not just free/temp-Premium
      // players. No expiry countdown here on purpose: a real subscription
      // auto-renews monthly rather than counting down to a fixed end.
      return InkWell(
        onTap: openPremium,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF164A2D), Color(0xFF1F8F4A)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Row(
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 30,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Premium Active • Unlimited stamina and category practice unlocked",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: openPremium,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5B2EFF), Color(0xFF9D4DFF), Color(0xFFFF4DA6)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.purple.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Row(
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              color: Colors.white,
              size: 30,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Upgrade to Premium",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "Unlock unlimited stamina and category-based quiz access",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  /// Practice Mode's own button, separate from [buildMainModeButton]
  /// because it needs a locked/grayed visual state for free players --
  /// same "review your mistakes" hook, but gated the same way locked
  /// categories are (see CategorySelectScreen): dimmed, a lock icon in
  /// place of the usual icon and arrow, and a watch-ad/go-Premium prompt
  /// instead of navigating straight in.
  Widget buildPracticeModeButton() {
    if (PlayerService.wrongQuestionIds.isEmpty) return const SizedBox.shrink();

    final bool locked = !PlayerService.isPremium;
    final int count = PlayerService.wrongQuestionIds.length;

    final List<Color> colors =
        locked
            ? const [Color(0xFF2A2E38), Color(0xFF20242C)]
            : const [Color(0xFF1F8F4A), Color(0xFF43C97A)];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        width: double.infinity,
        height: 96,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          onPressed:
              locked ? _showPracticeLockedPrompt : openPracticeMode,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(22),
              border:
                  locked
                      ? Border.all(color: Colors.white10)
                      : null,
              boxShadow:
                  locked
                      ? []
                      : [
                        BoxShadow(
                          color: colors.last.withValues(alpha: 0.25),
                          blurRadius: 18,
                          offset: const Offset(0, 10),
                        ),
                      ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: locked ? 0.06 : 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      locked
                          ? Icons.lock_rounded
                          : Icons.replay_circle_filled_rounded,
                      color: locked ? Colors.white38 : Colors.white,
                      size: locked ? 24 : 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Practice Mode",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: locked ? Colors.white54 : Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          locked
                              ? "Review & practice wrong answers — Premium"
                              : "$count question(s) to review • no timer, free",
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            color:
                                locked
                                    ? Colors.white38
                                    : Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    locked
                        ? Icons.lock_outline_rounded
                        : Icons.arrow_forward_ios_rounded,
                    color: locked ? Colors.white38 : Colors.white,
                    size: locked ? 20 : 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMainModeButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SizedBox(
        width: double.infinity,
        height: 96,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.zero,
            elevation: 0,
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
          ),
          onPressed: onTap,
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.2,
                            color: Colors.white.withValues(alpha: 0.88),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "MindSprint Trivia",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white10),
              ),
              child: IconButton(
                onPressed: openSettings,
                icon: const Icon(Icons.settings),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            children: [
              GestureDetector(
                onTap: openProfile,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1D2B64), Color(0xFF4F8CFF)],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.18),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      buildTopAvatar(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PlayerService.username,
                              style: const TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "Player Dashboard",
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              buildStreakCard(),
              StaminaBar(),
              const SizedBox(height: 20),
              // Leaderboard is now reached via the "See where you rank" row
              // built into this card, instead of its own separate button
              // further down the screen.
              buildLeagueProgressCard(),
              const SizedBox(height: 22),
              buildMainModeButton(
                title: "Normal Mode",
                subtitle:
                    PlayerService.isPremium
                        ? "Choose your category"
                        : "Mixed quiz (Upgrade for categories)",
                icon: Icons.school_rounded,
                colors: const [Color(0xFF355CFF), Color(0xFF4F8CFF)],
                onTap: () async {
                  await ModeEntryHelper.openNormalMode(context);
                  await refreshData();
                },
              ),
              buildMainModeButton(
                title: "Rapid Fire",
                subtitle: "Always mixed • 90 seconds • streak bonus",
                icon: Icons.flash_on_rounded,
                colors: const [Color(0xFF9C27B0), Color(0xFFFF5E62)],
                onTap: () async {
                  await ModeEntryHelper.openRapidMode(context);
                  await refreshData();
                },
              ),
              buildPracticeModeButton(),
              // Premium status/upsell is the last thing on the screen now --
              // it already says everything the old footer caption below it
              // used to repeat, so that caption was removed.
              const SizedBox(height: 12),
              buildPremiumCard(),
            ],
          ),
        ),
      ),
    );
  }
}
