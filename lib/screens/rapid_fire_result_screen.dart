import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'rapid_fire_screen.dart';
import '../services/stamina_service.dart';
import '../services/player_service.dart';
import '../services/usage_limit_service.dart';

class RapidFireResultScreen extends StatefulWidget {
  final int score;
  final int correct;
  final int wrong;
  final int bestStreak;
  final String weakestCategory;

  const RapidFireResultScreen({
    super.key,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.bestStreak,
    required this.weakestCategory,
  });

  @override
  State<RapidFireResultScreen> createState() => _RapidFireResultScreenState();
}

class _RapidFireResultScreenState extends State<RapidFireResultScreen> {
  bool saved = false;

  @override
  void initState() {
    super.initState();
    saveXp();
  }

  void saveXp() async {
    if (!saved) {
      await PlayerService.loadPlayer();
      int xpToAdd = widget.score > 0 ? widget.score : 0;
      await PlayerService.addXp(xpToAdd);
      saved = true;
    }

    if (mounted) {
      setState(() {});
    }
  }

  void showInfo() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Rapid Fire Scoring"),
            content: const Text(
              "• Correct answer = +20 XP\n"
              "• Wrong answer = -15 XP\n"
              "• Streak bonus starts from 3 correct answers in a row\n"
              "• Streak bonus = streak number × 10\n"
              "• Example: 4th correct in a streak = +20 +40",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("OK"),
              ),
            ],
          ),
    );
  }

  void playAgain() async {
    final canStart = await UsageLimitService.canStartRapidFire();

    if (!canStart) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Daily Rapid Fire limit reached. Premium unlocks unlimited rounds.",
          ),
        ),
      );
      return;
    }

    bool canPlay = await StaminaService.useStamina(20);

    if (!canPlay) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Not enough stamina!")));
      return;
    }

    await UsageLimitService.recordRapidFireRoundStarted();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const RapidFireScreen(category: "Mixed"),
      ),
    );
  }

  void goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  Widget buildStatCard(String title, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF181C24),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildUpsellCard() {
    if (PlayerService.isPremium) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Premium Advantage",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your weakest category was ${widget.weakestCategory}. Premium lets you practice weak areas directly in Normal Mode.",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final savedXp = widget.score > 0 ? widget.score : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rapid Fire Result"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(onPressed: showInfo, icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4B1D95), Color(0xFFFF5E62)],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Final Score",
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "${widget.score} XP",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    "Current League: ${PlayerService.getLeague()}",
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                buildStatCard("Correct", "${widget.correct}", Colors.green),
                const SizedBox(width: 12),
                buildStatCard("Wrong", "${widget.wrong}", Colors.redAccent),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                buildStatCard(
                  "Best Streak",
                  "${widget.bestStreak}",
                  Colors.orange,
                ),
                const SizedBox(width: 12),
                buildStatCard("XP Saved", "$savedXp", Colors.amber),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                "Weakest Category: ${widget.weakestCategory}",
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            buildUpsellCard(),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: playAgain,
                child: const Text("Play Again"),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: goHome,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF232A36),
                ),
                child: const Text("Main Menu"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
