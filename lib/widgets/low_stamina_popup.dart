import 'package:flutter/material.dart';

enum LowStaminaAction { watchAd, goPremium, close }

class LowStaminaPopup extends StatelessWidget {
  final int currentStamina;
  final int requiredStamina;
  final Future<bool> Function() onWatchAd;
  final Future<bool> Function() onGoPremium;

  const LowStaminaPopup({
    super.key,
    required this.currentStamina,
    required this.requiredStamina,
    required this.onWatchAd,
    required this.onGoPremium,
  });

  static Future<LowStaminaAction?> show({
    required BuildContext context,
    required int currentStamina,
    required int requiredStamina,
    required Future<bool> Function() onWatchAd,
    required Future<bool> Function() onGoPremium,
  }) {
    return showDialog<LowStaminaAction>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => LowStaminaPopup(
            currentStamina: currentStamina,
            requiredStamina: requiredStamina,
            onWatchAd: onWatchAd,
            onGoPremium: onGoPremium,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final int shortBy =
        (requiredStamina - currentStamina) > 0
            ? (requiredStamina - currentStamina)
            : 0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF121821),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFF2A3342)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFFFB347), Color(0xFFFF7A18)],
                ),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                color: Colors.white,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              "Not Enough Stamina",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "You need $requiredStamina stamina to start this mode, but you currently have $currentStamina.",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2230),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF2E3A4F)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Short by",
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    "$shortBy stamina",
                    style: const TextStyle(
                      color: Color(0xFFFFB347),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ActionCard(
              title: "Watch Ad",
              subtitle: "Get +20 stamina instantly",
              icon: Icons.ondemand_video_rounded,
              iconColor: const Color(0xFF68D5FF),
              backgroundColor: const Color(0xFF182332),
              borderColor: const Color(0xFF29445F),
              onTap: () async {
                final bool success = await onWatchAd();
                if (success && context.mounted) {
                  Navigator.of(context).pop(LowStaminaAction.watchAd);
                }
              },
            ),
            const SizedBox(height: 12),
            _PremiumActionCard(
              onTap: () async {
                final bool success = await onGoPremium();
                if (success && context.mounted) {
                  Navigator.of(context).pop(LowStaminaAction.goPremium);
                }
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop(LowStaminaAction.close);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF3B4659)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  "Close",
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white54,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumActionCard extends StatelessWidget {
  final VoidCallback onTap;

  const _PremiumActionCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          width: double.infinity,
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF5B2EFF), Color(0xFF9D4DFF), Color(0xFFFF4DA6)],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Go Premium",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "Unlock unlimited stamina and premium-only category quizzes",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13.3,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
