import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/stamina_service.dart';

class StaminaBar extends StatelessWidget {
  const StaminaBar({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isPremium = PlayerService.isPremium;
    final int current = StaminaService.visibleStamina;
    final int max = StaminaService.maxStamina;

    double progress = current / max;
    if (progress > 1) progress = 1;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// Top Row
          Row(
            children: [
              Icon(
                isPremium ? Icons.workspace_premium : Icons.bolt_rounded,
                color: isPremium ? Colors.amber : Colors.orange,
              ),
              const SizedBox(width: 8),

              /// Title
              const Text(
                "Stamina",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const Spacer(),

              /// Value
              if (isPremium)
                const Text(
                  "∞ Unlimited",
                  style: TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                )
              else
                Text(
                  "$current / $max",
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          /// Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: isPremium ? 1 : progress,
              minHeight: 12,
              backgroundColor: const Color(0xFF2B3242),
              valueColor: AlwaysStoppedAnimation<Color>(
                isPremium ? Colors.amber : Colors.orange,
              ),
            ),
          ),

          const SizedBox(height: 8),

          /// Bottom Text
          Text(
            isPremium
                ? "Unlimited stamina active"
                : "1 stamina regenerates every 4 minutes",
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
