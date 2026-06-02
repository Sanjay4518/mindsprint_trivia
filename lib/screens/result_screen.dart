import 'package:flutter/material.dart';
import 'normal_mode_screen.dart';
import 'home_screen.dart';
import '../services/stamina_service.dart';
import '../services/player_service.dart';
import '../services/usage_limit_service.dart';

class ResultScreen extends StatefulWidget {
  final int score;
  final int correct;
  final int wrong;
  final String weakestCategory;

  const ResultScreen({
    super.key,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.weakestCategory,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  double accuracy = 0;
  int xpBonus = 0;
  int totalXpEarned = 0;
  String badge = "";
  String message = "";
  String rewardText = "";
  bool saved = false;

  @override
  void initState() {
    super.initState();
    calculateAndSave();
  }

  void calculateAndSave() async {
    int total = widget.correct + widget.wrong;

    if (total > 0) {
      accuracy = (widget.correct / total) * 100;
    }

    if (accuracy == 100) {
      xpBonus = 500;
      rewardText = "🔥 Perfect! Full stamina restored!";
      StaminaService.currentStamina = StaminaService.maxStamina;
    } else if (accuracy >= 90) {
      xpBonus = 500;
      rewardText = "⚡ Excellent! Stamina refunded!";
      StaminaService.currentStamina += StaminaService.lastUsedStamina;
    } else if (accuracy >= 70) {
      xpBonus = 300;
      rewardText = "💪 Great performance!";
    } else if (accuracy >= 50) {
      xpBonus = 200;
      rewardText = "👍 Good job!";
    } else if (accuracy >= 40) {
      xpBonus = 100;
      rewardText = "📈 Keep improving!";
    }

    if (StaminaService.currentStamina > StaminaService.maxStamina) {
      StaminaService.currentStamina = StaminaService.maxStamina;
    }

    totalXpEarned = widget.score + xpBonus;
    badge = PlayerService.getPerformanceBadge(accuracy);
    message = PlayerService.getPerformanceMessage(accuracy);

    if (!saved) {
      await PlayerService.loadPlayer();
      await PlayerService.recordNormalResult(
        xpEarned: totalXpEarned,
        correct: widget.correct,
        wrong: widget.wrong,
      );
      await StaminaService.saveStamina();
      saved = true;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Color getBadgeColor() {
    if (accuracy >= 90) return Colors.green;
    if (accuracy >= 70) return Colors.blue;
    if (accuracy >= 50) return Colors.orange;
    return Colors.redAccent;
  }

  void showInfo() {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text("Scoring Info"),
            content: const Text(
              "Normal Mode:\n"
              "• Correct answer = +20 XP\n"
              "• Wrong answer = 0 XP\n"
              "• Timeout counts as mistake\n\n"
              "Accuracy Bonus:\n"
              "• 100% → +500 XP + Full Stamina Refill\n"
              "• 90%+ → +500 XP + Stamina Refund\n"
              "• 70%+ → +300 XP\n"
              "• 50%+ → +200 XP\n"
              "• 40%+ → +100 XP\n\n"
              "Rapid Fire uses separate streak bonuses.",
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
    const questionCount = 12;
    final canStart = await UsageLimitService.canStartNormalQuestionSet(
      questionCount,
    );

    if (!canStart) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Daily free question limit reached. Premium unlocks unlimited practice.",
          ),
        ),
      );
      return;
    }

    bool canPlay = await StaminaService.useStamina(15);

    if (!canPlay) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Not enough stamina!")));
      return;
    }

    await UsageLimitService.recordNormalQuestionsStarted(questionCount);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => const NormalModeScreen(category: "Mixed"),
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
            "Upgrade to Premium",
            style: TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Your weakest area is ${widget.weakestCategory}. Premium users can practice by category and target weak topics directly.",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Game Result"),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(onPressed: showInfo, icon: const Icon(Icons.info_outline)),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1D2B64), Color(0xFF4F8CFF)],
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

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: getBadgeColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: getBadgeColor()),
                ),
                child: Column(
                  children: [
                    Text(
                      badge,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: getBadgeColor(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    if (rewardText.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        rewardText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),

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
                    "Accuracy",
                    "${accuracy.toStringAsFixed(1)}%",
                    Colors.orange,
                  ),
                  const SizedBox(width: 12),
                  buildStatCard("Bonus", "$xpBonus", Colors.amber),
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

              const SizedBox(height: 20),

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
      ),
    );
  }
}
