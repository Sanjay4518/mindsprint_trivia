import 'dart:async';
import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/question_service.dart';
import '../services/stamina_service.dart';
import '../services/audio_service.dart';
import '../services/player_service.dart';
import 'rapid_fire_result_screen.dart';

class RapidFireScreen extends StatefulWidget {
  final String category;

  const RapidFireScreen({super.key, this.category = "Mixed"});

  @override
  State<RapidFireScreen> createState() => _RapidFireScreenState();
}

class _RapidFireScreenState extends State<RapidFireScreen>
    with SingleTickerProviderStateMixin {
  List<Question> questions = [];
  int currentQuestionIndex = 0;

  int score = 0;
  int totalTimeLeft = 90;
  int correctAnswers = 0;
  int wrongAnswers = 0;
  int streak = 0;
  int bestStreak = 0;

  Timer? timer;
  int? selectedAnswer;
  bool isAnswered = false;

  String? xpPopupText;
  double xpPopupOpacity = 0.0;
  double xpPopupOffset = 20.0;

  late AnimationController timerPulseController;

  final Map<String, int> categoryTotal = {};
  final Map<String, int> categoryWrong = {};

  @override
  void initState() {
    super.initState();
    loadQuestions();

    timerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    startTimer();
  }

  void loadQuestions() {
    questions = QuestionService.getQuestionsForRapidFire(count: 20);

    categoryTotal.clear();
    categoryWrong.clear();

    for (final q in questions) {
      categoryTotal[q.category] = (categoryTotal[q.category] ?? 0) + 1;
      categoryWrong.putIfAbsent(q.category, () => 0);
    }
  }

  void startTimer() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        totalTimeLeft--;
      });

      if (totalTimeLeft <= 10 && totalTimeLeft > 0) {
        if (!timerPulseController.isAnimating) {
          timerPulseController.repeat(reverse: true);
        }
      } else {
        timerPulseController.stop();
        timerPulseController.value = 1.0;
      }

      if (totalTimeLeft <= 0) {
        endQuiz();
      }
    });
  }

  void showXpPopup(String text) {
    setState(() {
      xpPopupText = text;
      xpPopupOpacity = 1.0;
      xpPopupOffset = 20.0;
    });

    Future.delayed(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      setState(() {
        xpPopupOffset = -10.0;
      });
    });

    Future.delayed(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() {
        xpPopupOpacity = 0.0;
      });
    });
  }

  void checkAnswer(int selectedIndex) {
    if (isAnswered || questions.isEmpty) return;

    setState(() {
      selectedAnswer = selectedIndex;
      isAnswered = true;
    });

    final currentQuestion = questions[currentQuestionIndex];
    final currentCategory = currentQuestion.category;

    if (selectedIndex == currentQuestion.correctIndex) {
      streak++;
      if (streak > bestStreak) bestStreak = streak;

      int gained = 20;
      if (streak >= 3) {
        gained += streak * 10;
      }

      score += gained;
      correctAnswers++;
      AudioService.playSfx('correct.wav');
      showXpPopup("+$gained XP");
    } else {
      streak = 0;
      score -= 15;
      wrongAnswers++;
      categoryWrong[currentCategory] =
          (categoryWrong[currentCategory] ?? 0) + 1;
      AudioService.playSfx('wrong.wav');
      showXpPopup("-15");
    }

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (totalTimeLeft > 0) {
        nextQuestion();
      }
    });
  }

  void nextQuestion() {
    if (questions.isEmpty) return;

    setState(() {
      currentQuestionIndex++;

      if (currentQuestionIndex >= questions.length) {
        loadQuestions();
        currentQuestionIndex = 0;
      }

      selectedAnswer = null;
      isAnswered = false;
    });
  }

  String getWeakestCategory() {
    String weakest = "None";
    double worstAccuracy = 101;

    for (final category in categoryTotal.keys) {
      final total = categoryTotal[category] ?? 0;
      final wrong = categoryWrong[category] ?? 0;
      final correct = total - wrong;
      final double accuracy = total == 0 ? 100.0 : (correct / total) * 100.0;

      if (accuracy < worstAccuracy) {
        worstAccuracy = accuracy;
        weakest = category;
      }
    }

    return weakest;
  }

  void endQuiz() {
    timer?.cancel();
    timerPulseController.stop();
    timerPulseController.value = 1.0;
    AudioService.playSfx('complete.wav');

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (context) => RapidFireResultScreen(
              score: score,
              correct: correctAnswers,
              wrong: wrongAnswers,
              bestStreak: bestStreak,
              weakestCategory: getWeakestCategory(),
            ),
      ),
    );
  }

  Color getOptionColor(int i, Question q) {
    if (!isAnswered) return const Color(0xFF2B2240);

    if (i == q.correctIndex) return Colors.green;
    if (i == selectedAnswer) return Colors.red;
    return const Color(0xFF2B2240);
  }

  @override
  void dispose() {
    timer?.cancel();
    timerPulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Rapid Fire")),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final q = questions[currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(title: const Text("Rapid Fire • Mixed")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.flash_on, color: Colors.orange),
                      const SizedBox(width: 5),
                      Text(
                        PlayerService.isPremium
                            ? "Unlimited"
                            : "${StaminaService.currentStamina}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.timer, color: Colors.red),
                      const SizedBox(width: 5),
                      Text(
                        "$totalTimeLeft",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber),
                      const SizedBox(width: 5),
                      Text(
                        "$score",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Streak: $streak",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "Best: $bestStreak",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Stack(
              alignment: Alignment.topCenter,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF181C24),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.category,
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        q.question,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 600),
                  top: xpPopupOffset,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 600),
                    opacity: xpPopupOpacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            xpPopupText != null && xpPopupText!.startsWith("-")
                                ? Colors.redAccent
                                : Colors.green,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        xpPopupText ?? "",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: ListView.builder(
                itemCount: q.options.length,
                itemBuilder: (context, i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: getOptionColor(i, q),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        onPressed: () => checkAnswer(i),
                        child: Text(
                          q.options[i],
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            ScaleTransition(
              scale: timerPulseController,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 22,
                ),
                decoration: BoxDecoration(
                  color:
                      totalTimeLeft <= 10
                          ? Colors.redAccent.withValues(alpha: 0.85)
                          : const Color(0xFF181C24),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color:
                        totalTimeLeft <= 10 ? Colors.redAccent : Colors.white10,
                  ),
                ),
                child: Text(
                  "⏱ $totalTimeLeft",
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
