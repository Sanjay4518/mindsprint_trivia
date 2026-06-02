import 'package:flutter/material.dart';
import 'dart:async';
import '../models/question.dart';
import '../services/question_service.dart';
import '../services/stamina_service.dart';
import '../services/audio_service.dart';
import '../services/player_service.dart';
import 'result_screen.dart';

class NormalModeScreen extends StatefulWidget {
  final String category;

  const NormalModeScreen({super.key, required this.category});

  @override
  State<NormalModeScreen> createState() => _NormalModeScreenState();
}

class _NormalModeScreenState extends State<NormalModeScreen>
    with SingleTickerProviderStateMixin {
  List<Question> questions = [];
  int currentQuestionIndex = 0;

  int score = 0;
  int lives = 3;
  int correctAnswers = 0;
  int wrongAnswers = 0;
  int timeLeft = 30;

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

    questions = QuestionService.getQuestionsForNormalMode(
      isPremium: PlayerService.isPremium,
      selectedCategory: widget.category,
      count: 12,
    );

    timerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    for (final q in questions) {
      categoryTotal[q.category] = (categoryTotal[q.category] ?? 0) + 1;
      categoryWrong.putIfAbsent(q.category, () => 0);
    }

    startTimer();
  }

  void startTimer() {
    timeLeft = 30;
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() {
        timeLeft--;
      });

      if (timeLeft <= 5 && timeLeft > 0) {
        if (!timerPulseController.isAnimating) {
          timerPulseController.repeat(reverse: true);
        }
      } else {
        timerPulseController.stop();
        timerPulseController.value = 1.0;
      }

      if (timeLeft == 0) {
        final currentCategory = questions[currentQuestionIndex].category;
        lives--;
        wrongAnswers++;
        categoryWrong[currentCategory] =
            (categoryWrong[currentCategory] ?? 0) + 1;

        timerPulseController.stop();
        timerPulseController.value = 1.0;

        if (lives == 0) {
          AudioService.playSfx('gameover.wav');
          endQuiz();
        } else {
          nextQuestion();
        }
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

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        xpPopupOpacity = 0.0;
      });
    });
  }

  void checkAnswer(int selectedIndex) {
    if (isAnswered) return;

    setState(() {
      selectedAnswer = selectedIndex;
      isAnswered = true;
    });

    timer?.cancel();
    timerPulseController.stop();
    timerPulseController.value = 1.0;

    final currentCategory = questions[currentQuestionIndex].category;

    if (selectedIndex == questions[currentQuestionIndex].correctIndex) {
      AudioService.playSfx('correct.wav');
      score += 20;
      correctAnswers++;
      showXpPopup("+20 XP");
    } else {
      AudioService.playSfx('wrong.wav');
      lives--;
      wrongAnswers++;
      categoryWrong[currentCategory] =
          (categoryWrong[currentCategory] ?? 0) + 1;
    }

    Future.delayed(const Duration(seconds: 1), () {
      if (lives == 0) {
        AudioService.playSfx('gameover.wav');
        endQuiz();
        return;
      }
      nextQuestion();
    });
  }

  void nextQuestion() {
    timer?.cancel();

    setState(() {
      if (currentQuestionIndex < questions.length - 1) {
        currentQuestionIndex++;
        selectedAnswer = null;
        isAnswered = false;
        xpPopupOpacity = 0.0;
        startTimer();
      } else {
        AudioService.playSfx('complete.wav');
        endQuiz();
      }
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

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (context) => ResultScreen(
              score: score,
              correct: correctAnswers,
              wrong: wrongAnswers,
              weakestCategory: getWeakestCategory(),
            ),
      ),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    timerPulseController.dispose();
    super.dispose();
  }

  Color getOptionColor(int i, Question q) {
    if (!isAnswered) return const Color(0xFF232A36);

    if (i == q.correctIndex) return Colors.green;
    if (i == selectedAnswer) return Colors.red;
    return const Color(0xFF232A36);
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final q = questions[currentQuestionIndex];

    return Scaffold(
      appBar: AppBar(title: Text("Normal Mode • ${widget.category}")),
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
                      const Icon(Icons.favorite, color: Colors.red),
                      const SizedBox(width: 5),
                      Text(
                        "$lives",
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.category,
                        style: const TextStyle(
                          color: Colors.blueAccent,
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
                  duration: const Duration(milliseconds: 650),
                  top: xpPopupOffset,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 650),
                    opacity: xpPopupOpacity,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.95),
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
                      duration: const Duration(milliseconds: 280),
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
                      timeLeft <= 5
                          ? Colors.redAccent.withValues(alpha: 0.85)
                          : const Color(0xFF181C24),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: timeLeft <= 5 ? Colors.redAccent : Colors.white10,
                  ),
                ),
                child: Text(
                  "⏱ $timeLeft",
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
