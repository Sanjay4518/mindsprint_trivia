import 'package:flutter/material.dart';

class GameInfoScreen extends StatelessWidget {
  const GameInfoScreen({super.key});

  Widget buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 18),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget buildInfoCard(String title, String content, {IconData? icon}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.blueAccent),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Game Info")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildSectionTitle("Normal Mode"),
            buildInfoCard(
              "How it works",
              "• Entry cost: 15 stamina\n"
                  "• 12 questions\n"
                  "• 30 seconds per question\n"
                  "• 3 lives total\n"
                  "• Free users play Mixed quizzes only\n"
                  "• Premium users can choose categories",
              icon: Icons.school_rounded,
            ),
            buildInfoCard(
              "Scoring",
              "• Correct answer: +20 XP\n"
                  "• Wrong answer: 0 XP\n"
                  "• Timeout counts as a mistake",
              icon: Icons.star_rounded,
            ),
            buildInfoCard(
              "Accuracy rewards",
              "• 100% accuracy → +500 XP + full stamina refill\n"
                  "• 90%+ accuracy → +500 XP + stamina refund\n"
                  "• 70%+ accuracy → +300 XP\n"
                  "• 50%+ accuracy → +200 XP\n"
                  "• 40%+ accuracy → +100 XP",
              icon: Icons.emoji_events_rounded,
            ),
            buildSectionTitle("Rapid Fire"),
            buildInfoCard(
              "How it works",
              "• Entry cost: 20 stamina\n"
                  "• 90 seconds total\n"
                  "• Always Mixed mode\n"
                  "• Questions keep coming until time ends",
              icon: Icons.flash_on_rounded,
            ),
            buildInfoCard(
              "Scoring",
              "• Correct answer: +20 XP\n"
                  "• Wrong answer: -15 XP\n"
                  "• Streak bonus starts from 3 correct answers in a row\n"
                  "• Streak bonus = streak number × 10",
              icon: Icons.local_fire_department_rounded,
            ),
            buildSectionTitle("Stamina System"),
            buildInfoCard(
              "Energy",
              "• Maximum stamina: 60\n"
                  "• Recharges automatically over time\n"
                  "• Normal Mode uses 15 stamina\n"
                  "• Rapid Fire uses 20 stamina",
              icon: Icons.bolt_rounded,
            ),
            buildInfoCard(
              "Low stamina plan",
              "• Rewarded ads can later give bonus stamina\n"
                  "• Premium users will get unlimited stamina",
              icon: Icons.ondemand_video_rounded,
            ),
            buildSectionTitle("Premium"),
            buildInfoCard(
              "Premium benefits",
              "• Category-based quizzes in Normal Mode\n"
                  "• No ads\n"
                  "• Unlimited stamina\n"
                  "• More focused practice features later",
              icon: Icons.workspace_premium_rounded,
            ),
            buildSectionTitle("Leaderboard"),
            buildInfoCard(
              "League system",
              "• Players compete inside leagues like Bronze, Silver, Gold, Platinum, Diamond\n"
                  "• Future updates can include promotion, demotion, and weekly resets",
              icon: Icons.leaderboard_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
