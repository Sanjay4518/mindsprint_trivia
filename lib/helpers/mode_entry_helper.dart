import 'package:flutter/material.dart';
import '../screens/category_select_screen.dart';
import '../screens/normal_mode_screen.dart';
import '../screens/premium_screen.dart';
import '../screens/rapid_fire_screen.dart';
import '../services/ad_service.dart';
import '../services/player_service.dart';
import '../services/server_time_service.dart';
import '../services/stamina_service.dart';
import '../services/usage_limit_service.dart';
import '../widgets/low_stamina_popup.dart';

class ModeEntryHelper {
  /// True while a mode entry is between "the player tapped" and "the quiz
  /// screen has actually been pushed." Every entry point below refuses to
  /// start a second one while it's set.
  ///
  /// Without this, a double-tap was genuinely destructive rather than just
  /// wasteful. Entry is not instant -- it awaits ServerTimeService.sync()
  /// (up to a 5s timeout on a bad connection), a profile load, and a
  /// stamina write -- and the button stays live and unchanged that whole
  /// time, so a second tap is easy. Both taps passed the stamina gate,
  /// spent the cost twice, and pushed two quiz screens. The buried one
  /// keeps its own timer running, and when it ends it calls
  /// Navigator.pushReplacement -- which replaces the TOPMOST route, not
  /// its own -- so a dead round would replace the round the player was
  /// actually playing and bank its own 0-correct result to their real
  /// stats, XP and leaderboard entry.
  ///
  /// Deliberately released just before the quiz screen is pushed (see
  /// _enterNormalMode/_enterRapidMode) rather than held for the lifetime
  /// of that screen. Once the quiz is on screen it covers the button, so
  /// there's nothing left to guard -- and holding it longer would break
  /// "Play Again," which calls back into this helper from the result
  /// screen while the original navigation future is still unresolved.
  static bool _entryInFlight = false;

  /// Same idea for the two rewarded-ad flows below. Loading and showing a
  /// rewarded ad takes seconds, during which the button that started it
  /// stays tappable; a second tap ran a second ad and consumed a second
  /// slot from that day's cap for one intended reward.
  static bool _adFlowInFlight = false;

  static const int normalCost = 15;
  static const int rapidCost = 20;
  // Deliberately shorter than the one-time Google sign-in bonus (30 min,
  // see PlayerService.claimGoogleSignInBonusIfNeeded) -- that one only ever
  // fires once per account, so it doesn't compete with Premium the way a
  // repeatable daily reward would. This one is capped at
  // UsageLimitService.freeTempPremiumUnlocksPerDay times *every* day, so it
  // needs to stay meaningfully short of "just play free all day" (was 30
  // min x 3/day = 90 min/day; now 15 min x 2/day = 30 min/day).
  static const Duration tempPremiumDuration = Duration(minutes: 15);

  /// Shared "watch an ad, get temporary Premium" flow. Used by the low
  /// stamina popup, the locked-category prompt, and the Premium screen, so
  /// the daily-cap check, ad-showing, and messaging only live in one place.
  /// Returns true if Premium was actually unlocked.
  static Future<bool> tryWatchAdForTemporaryPremium(
    BuildContext context,
  ) async {
    // See _adFlowInFlight -- a double-tap here used to burn two of the
    // player's daily unlocks for one intended reward, since neither
    // attempt had recorded against the cap yet when the other checked it.
    if (_adFlowInFlight) return false;
    _adFlowInFlight = true;

    try {
      // Freshens the server-time offset right before stamping this reward's
      // expiry, so the window a device-clock trick could slip through is as
      // small as possible. See ServerTimeService.
      await ServerTimeService.sync();

      final bool underCap = await UsageLimitService.canWatchTempPremiumAd();

      if (!context.mounted) return false;

      if (!underCap) {
        _showDailyLimitSnackBar(
          context,
          "You've used today's ${UsageLimitService.freeTempPremiumUnlocksPerDay} free Premium unlocks. Come back tomorrow, or go Premium for unlimited access.",
        );
        return false;
      }

      final bool earnedReward = await AdService.instance.showRewardedAd(
        onRewardEarned: () async {
          await PlayerService.grantTemporaryPremium(tempPremiumDuration);
          await UsageLimitService.recordTempPremiumUnlockWatched();
        },
      );

      if (!earnedReward && context.mounted) {
        await _showAdNotReadyDialog(context);
      }

      return earnedReward;
    } finally {
      _adFlowInFlight = false;
    }
  }

  /// Shared "watch an ad for +20 stamina" flow, used by both the Normal
  /// Mode and Rapid Fire low-stamina popups. Capped like the temp-Premium
  /// ad reward above (see UsageLimitService.freeStaminaAdsPerDay) -- added
  /// 2026-09-02. This used to be completely uncapped, letting a free
  /// player bypass the whole stamina economy for the cost of one ~30s ad
  /// per game, unlike every other rewarded-ad mechanic in the app.
  static Future<bool> _watchAdForStamina(BuildContext context) async {
    // See _adFlowInFlight -- same double-tap problem as the temp-Premium
    // flow above, against the daily stamina-ad cap instead.
    if (_adFlowInFlight) return false;
    _adFlowInFlight = true;

    try {
      final bool underCap = await UsageLimitService.canWatchStaminaAd();

      if (!context.mounted) return false;

      if (!underCap) {
        _showDailyLimitSnackBar(
          context,
          "You've used today's ${UsageLimitService.freeStaminaAdsPerDay} free stamina-refill ads. Come back tomorrow, or go Premium for unlimited stamina.",
        );
        return false;
      }

      final bool earnedReward = await AdService.instance.showRewardedAd(
        onRewardEarned: () async {
          // Grant first, record the cap second, on purpose. Both now run
          // to completion before showRewardedAd resolves (see
          // AdService.showRewardedAd), so the window between them is tiny
          // either way -- but if the process does die in between, giving
          // the player the reward they watched an ad for and losing a cap
          // slot is the kinder failure than the reverse.
          await StaminaService.addStamina(20);
          await UsageLimitService.recordStaminaAdWatched();
        },
      );

      if (!earnedReward && context.mounted) {
        await _showAdNotReadyDialog(context);
      }

      return earnedReward;
    } finally {
      _adFlowInFlight = false;
    }
  }

  /// Opens the category picker for Normal Mode. Just navigation -- no
  /// stamina or daily-limit is spent here. Browsing categories is free for
  /// everyone; the actual cost is charged in [startNormalModeForCategory],
  /// only once a category is actually tapped.
  static Future<void> openNormalMode(BuildContext context) async {
    if (_entryInFlight) return;
    _entryInFlight = true;

    try {
      // Freshens the server-time offset right before the stamina gate runs,
      // so regen can't be tricked by a device-clock change. See
      // ServerTimeService.
      await ServerTimeService.sync();
      await PlayerService.loadPlayer();
      await StaminaService.refreshStamina();

      if (!context.mounted) return;

      // Released before the navigation await, not after -- see
      // _entryInFlight. The category picker covers the button that got us
      // here, and this push doesn't resolve until the player comes all
      // the way back out of it.
      _entryInFlight = false;

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategorySelectScreen()),
      );
    } finally {
      _entryInFlight = false;
    }
  }

  /// Called from the category picker when the user taps an available
  /// category (always "Mixed" for free users; any category for premium).
  /// This is where the daily-limit check, stamina check, and low-stamina
  /// popup now live, so opening/browsing the picker itself stays free.
  static Future<void> startNormalModeForCategory(
    BuildContext context,
    String category,
  ) async {
    if (!context.mounted) return;
    if (_entryInFlight) return;
    _entryInFlight = true;

    try {
      await _startNormalModeForCategoryInner(context, category);
    } finally {
      _entryInFlight = false;
    }
  }

  static Future<void> _startNormalModeForCategoryInner(
    BuildContext context,
    String category,
  ) async {
    // Freshens the server-time offset and the real stamina count right
    // before the gate check runs -- see _openRapidModeInner, which already
    // does this. This entry point was missing it: the category picker
    // (CategorySelectScreen) can be browsed for as long as the player
    // likes before a category is tapped, with no refresh of its own, so
    // without this the gate below could run against a StaminaService value
    // that's only as fresh as HomeScreen's background ticker happened to
    // leave it -- e.g. a free player who waited out enough regen to afford
    // this round could still see a spurious "Not Enough Stamina" popup.
    await ServerTimeService.sync();
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if (_canEnter(normalCost)) {
      await _enterNormalMode(context, category);
      return;
    }

    final action = await LowStaminaPopup.show(
      context: context,
      currentStamina: StaminaService.currentStamina,
      requiredStamina: normalCost,
      onWatchAd: () => _watchAdForStamina(context),
      onUnlockTempPremium: () => tryWatchAdForTemporaryPremium(context),
      onGoPremium: () async {
        final bool? activated = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        return activated ?? false;
      },
    );

    // Freshens the server-time offset right before the stamina gate runs,
    // so regen can't be tricked by a device-clock change. See
    // ServerTimeService.
    await ServerTimeService.sync();
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if ((action == LowStaminaAction.watchAd ||
            action == LowStaminaAction.unlockTempPremium ||
            action == LowStaminaAction.goPremium) &&
        _canEnter(normalCost)) {
      await _enterNormalMode(context, category);
    }
  }

  static Future<void> openRapidMode(BuildContext context) async {
    if (_entryInFlight) return;
    _entryInFlight = true;

    try {
      await _openRapidModeInner(context);
    } finally {
      _entryInFlight = false;
    }
  }

  static Future<void> _openRapidModeInner(BuildContext context) async {
    // Freshens the server-time offset right before the stamina gate runs,
    // so regen can't be tricked by a device-clock change. See
    // ServerTimeService.
    await ServerTimeService.sync();
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if (_canEnter(rapidCost)) {
      await _enterRapidMode(context);
      return;
    }

    final action = await LowStaminaPopup.show(
      context: context,
      currentStamina: StaminaService.currentStamina,
      requiredStamina: rapidCost,
      onWatchAd: () => _watchAdForStamina(context),
      onUnlockTempPremium: () => tryWatchAdForTemporaryPremium(context),
      onGoPremium: () async {
        final bool? activated = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        return activated ?? false;
      },
    );

    // Freshens the server-time offset right before the stamina gate runs,
    // so regen can't be tricked by a device-clock change. See
    // ServerTimeService.
    await ServerTimeService.sync();
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if ((action == LowStaminaAction.watchAd ||
            action == LowStaminaAction.unlockTempPremium ||
            action == LowStaminaAction.goPremium) &&
        _canEnter(rapidCost)) {
      await _enterRapidMode(context);
    }
  }

  static bool _canEnter(int required) {
    if (PlayerService.isPremium) return true;
    return StaminaService.currentStamina >= required;
  }

  static Future<void> _enterNormalMode(
    BuildContext context,
    String category,
  ) async {
    bool spentStamina = false;

    if (!PlayerService.isPremium) {
      final bool canUse = await StaminaService.useStamina(normalCost);
      if (!canUse) return;
      spentStamina = true;
    } else {
      // Premium skips useStamina() entirely, which is also the only thing
      // that resets lastUsedStamina -- so without this it kept whatever
      // the last *free* round charged. A 90%+ finish refunds
      // lastUsedStamina (see ResultScreen), so if a temporary Premium
      // window lapsed mid-round the player was refunded stamina this
      // round never cost them.
      StaminaService.lastUsedStamina = 0;
    }

    if (!context.mounted) {
      if (spentStamina) {
        // The round never actually started -- e.g. the category picker
        // was popped, or the app was backgrounded, while the useStamina()
        // write above was still queued behind other pending writes in
        // StaminaService's own _prefsChain. Refund rather than silently
        // charging a free player for a round they never got to play.
        await StaminaService.addStamina(normalCost);
      }
      return;
    }

    // Released before the navigation await -- see _entryInFlight. The
    // check-and-spend above is the part that had to be atomic; from here
    // the quiz screen covers the button.
    _entryInFlight = false;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NormalModeScreen(category: category)),
    );
  }

  static Future<void> _enterRapidMode(BuildContext context) async {
    bool spentStamina = false;

    if (!PlayerService.isPremium) {
      final bool canUse = await StaminaService.useStamina(rapidCost);
      if (!canUse) return;
      spentStamina = true;
    } else {
      // See _enterNormalMode.
      StaminaService.lastUsedStamina = 0;
    }

    if (!context.mounted) {
      // See _enterNormalMode -- same refund reasoning.
      if (spentStamina) {
        await StaminaService.addStamina(rapidCost);
      }
      return;
    }

    _entryInFlight = false;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RapidFireScreen()),
    );
  }

  static Future<void> _showAdNotReadyDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              "Ad Not Ready",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "The rewarded ad is not ready yet. Please wait a moment and try again.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  static void _showDailyLimitSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
