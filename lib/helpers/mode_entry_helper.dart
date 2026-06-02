import 'package:flutter/material.dart';
import '../screens/category_select_screen.dart';
import '../screens/normal_mode_screen.dart';
import '../screens/premium_screen.dart';
import '../screens/rapid_fire_screen.dart';
import '../services/ad_service.dart';
import '../services/player_service.dart';
import '../services/stamina_service.dart';
import '../services/usage_limit_service.dart';
import '../widgets/low_stamina_popup.dart';

class ModeEntryHelper {
  static const int normalCost = 15;
  static const int rapidCost = 20;
  static const int normalQuestionCount = 12;

  static Future<void> openNormalMode(BuildContext context) async {
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    final canStartNormal = await UsageLimitService.canStartNormalQuestionSet(
      normalQuestionCount,
    );

    if (!context.mounted) return;

    if (!canStartNormal) {
      _showDailyLimitSnackBar(
        context,
        "Daily free question limit reached. Premium unlocks unlimited practice.",
      );
      return;
    }

    if (_canEnter(normalCost)) {
      await _enterNormalMode(context);
      return;
    }

    final action = await LowStaminaPopup.show(
      context: context,
      currentStamina: StaminaService.currentStamina,
      requiredStamina: normalCost,
      onWatchAd: () async {
        final bool earnedReward = await AdService.instance.showRewardedAd(
          onRewardEarned: () async {
            await StaminaService.addStamina(20);
          },
        );

        if (!earnedReward && context.mounted) {
          await _showAdNotReadyDialog(context);
        }

        return earnedReward;
      },
      onGoPremium: () async {
        final bool? activated = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        return activated ?? false;
      },
    );

    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if ((action == LowStaminaAction.watchAd ||
            action == LowStaminaAction.goPremium) &&
        _canEnter(normalCost)) {
      await _enterNormalMode(context);
    }
  }

  static Future<void> openRapidMode(BuildContext context) async {
    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    final canStartRapid = await UsageLimitService.canStartRapidFire();

    if (!context.mounted) return;

    if (!canStartRapid) {
      _showDailyLimitSnackBar(
        context,
        "Daily Rapid Fire limit reached. Premium unlocks unlimited rounds.",
      );
      return;
    }

    if (_canEnter(rapidCost)) {
      await _enterRapidMode(context);
      return;
    }

    final action = await LowStaminaPopup.show(
      context: context,
      currentStamina: StaminaService.currentStamina,
      requiredStamina: rapidCost,
      onWatchAd: () async {
        final bool earnedReward = await AdService.instance.showRewardedAd(
          onRewardEarned: () async {
            await StaminaService.addStamina(20);
          },
        );

        if (!earnedReward && context.mounted) {
          await _showAdNotReadyDialog(context);
        }

        return earnedReward;
      },
      onGoPremium: () async {
        final bool? activated = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const PremiumScreen()),
        );
        return activated ?? false;
      },
    );

    await PlayerService.loadPlayer();
    await StaminaService.refreshStamina();

    if (!context.mounted) return;

    if ((action == LowStaminaAction.watchAd ||
            action == LowStaminaAction.goPremium) &&
        _canEnter(rapidCost)) {
      await _enterRapidMode(context);
    }
  }

  static bool _canEnter(int required) {
    if (PlayerService.isPremium) return true;
    return StaminaService.currentStamina >= required;
  }

  static Future<void> _enterNormalMode(BuildContext context) async {
    if (!PlayerService.isPremium) {
      final bool canUse = await StaminaService.useStamina(normalCost);
      if (!canUse) return;
      await UsageLimitService.recordNormalQuestionsStarted(
        normalQuestionCount,
      );
    }

    if (!context.mounted) return;

    if (PlayerService.isPremium) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CategorySelectScreen()),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NormalModeScreen(category: "Mixed")),
      );
    }
  }

  static Future<void> _enterRapidMode(BuildContext context) async {
    if (!PlayerService.isPremium) {
      final bool canUse = await StaminaService.useStamina(rapidCost);
      if (!canUse) return;
      await UsageLimitService.recordRapidFireRoundStarted();
    }

    if (!context.mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RapidFireScreen(category: "Mixed")),
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
