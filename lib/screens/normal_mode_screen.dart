import 'package:flutter/material.dart';
import 'dart:async';
import '../models/question.dart';
import '../services/question_service.dart';
import '../services/stamina_service.dart';
import '../services/audio_service.dart';
import '../services/player_service.dart';
import '../services/ad_service.dart';
import 'result_screen.dart';

class NormalModeScreen extends StatefulWidget {
  final String category;

  const NormalModeScreen({super.key, required this.category});

  @override
  State<NormalModeScreen> createState() => _NormalModeScreenState();
}

class _NormalModeScreenState extends State<NormalModeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // Guards endQuiz() against running twice -- e.g. the question timer
  // hitting zero at almost the same moment the player confirms Exit.
  // Without this, both paths could save the result and navigate,
  // double-counting XP/stats. See endQuiz().
  bool _ended = false;

  // True while the exit-confirmation dialog is on screen -- lets endQuiz()
  // know to dismiss it before navigating, so a naturally-timed game-over
  // (lives hit 0, timer expires) that fires while the player is still
  // deciding doesn't leave the dialog's route in an inconsistent state.
  bool _exitDialogOpen = false;

  String? xpPopupText;
  double xpPopupOpacity = 0.0;
  double xpPopupOffset = 20.0;

  late AnimationController timerPulseController;

  final Map<String, int> categoryTotal = {};
  final Map<String, int> categoryWrong = {};
  final List<String> missedQuestionIds = [];

  // Anti-cheat: if the player backgrounds the app mid-question (e.g. to
  // search for the answer elsewhere) and comes back, that question is
  // auto-marked wrong. A short grace window avoids punishing quick,
  // accidental app-switches (like pulling down the notification shade).
  DateTime? _backgroundedAt;
  // Widened from 2s to 5s (2026-09-04) -- 2 seconds was tight enough to
  // trip on a routine interruption (glancing at a notification banner, an
  // OS permission dialog popping over the app) that had nothing to do
  // with actually leaving to look up an answer.
  static const Duration _backgroundGraceThreshold = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

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

    // categoryTotal is deliberately NOT pre-populated from the full
    // `questions` list here -- a round can end early (lives hit 0) before
    // every question is faced, and since getWeakestCategory() derives
    // correct as total - wrong, pre-counting every question as "total"
    // silently counted every never-seen question as a correct answer for
    // its category. Each question is now counted (categoryTotal++) only
    // at the moment it's actually faced -- see checkAnswer, the timeout
    // branch in _startTicking, and _failCurrentQuestionForLeavingApp --
    // matching the fix already applied to RapidFireScreen.loadQuestions()
    // for the identical bug.

    // Guard against an empty question bank (e.g. the JSON failed to load
    // this session -- see splash_screen.dart's initializeApp) starting a
    // timer that would eventually index into an empty `questions` list
    // and crash. build() below already shows a loading spinner instead of
    // the quiz UI whenever questions is empty.
    if (questions.isNotEmpty) {
      startTimer();
    }
  }

  void startTimer() {
    timeLeft = 30;
    _startTicking();
  }

  void _startTicking() {
    timer?.cancel();

    timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _ended) {
        t.cancel();
        return;
      }

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
        isAnswered = true;
        lives--;
        wrongAnswers++;
        // Counted here, not at round load -- this is the moment the
        // question was actually faced. See initState() for why.
        categoryTotal[currentCategory] =
            (categoryTotal[currentCategory] ?? 0) + 1;
        categoryWrong[currentCategory] =
            (categoryWrong[currentCategory] ?? 0) + 1;
        missedQuestionIds.add(questions[currentQuestionIndex].id);

        timerPulseController.stop();
        timerPulseController.value = 1.0;

        // Same one-second delay as checkAnswer()'s manual-answer path,
        // rather than advancing immediately -- without it, getOptionColor()
        // never gets a frame to actually paint the correct-answer
        // highlight this branch sets isAnswered=true for, since everything
        // above ran synchronously inside this same Timer.periodic tick.
        // Cancel the ticking timer now so it can't also fire the next
        // second's tick against a question that's already moved on.
        t.cancel();
        Future.delayed(const Duration(seconds: 1), () {
          if (!mounted) return;
          if (lives == 0) {
            AudioService.playSfx('gameover.wav');
            endQuiz();
          } else {
            nextQuestion();
          }
        });
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
    if (isAnswered || _ended) return;

    setState(() {
      selectedAnswer = selectedIndex;
      isAnswered = true;
    });

    timer?.cancel();
    timerPulseController.stop();
    timerPulseController.value = 1.0;

    final currentCategory = questions[currentQuestionIndex].category;
    // Counted here, not at round load -- this is the moment the question
    // was actually faced. See initState() for why.
    categoryTotal[currentCategory] = (categoryTotal[currentCategory] ?? 0) + 1;

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
      missedQuestionIds.add(questions[currentQuestionIndex].id);
    }

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (lives == 0) {
        AudioService.playSfx('gameover.wav');
        endQuiz();
        return;
      }
      nextQuestion();
    });
  }

  void nextQuestion() {
    if (_ended) return;
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
    // A category-specific round (Premium's category picker in Normal Mode)
    // only ever has one key in categoryTotal -- every question came from
    // the single category the player chose. In that case any wrong answer
    // trivially "wins" the loop below and gets reported as the player's
    // weakest category, which is misleading: there was nothing else to
    // compare it against, and it isn't a weakness discovered by this
    // round, just the one category the player deliberately chose to
    // practice. "Weakest category" is only a meaningful signal for a Mixed
    // round, which spans multiple categories by design.
    if (categoryTotal.length <= 1) return "None";

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

    // On a flawless round every category sits at 100%, so the loop above
    // would just name whichever category happened to come first -- and the
    // result screen would tell a player who got everything right that
    // Current Affairs is their weak area. "None" is the honest answer;
    // callers (see ResultScreen) render that case differently.
    if (worstAccuracy >= 100) return "None";

    return weakest;
  }

  Future<void> endQuiz({bool exitedEarly = false}) async {
    // Several different paths can reach endQuiz() -- the question timer
    // hitting zero, the last question being answered, running out of
    // lives, the backgrounding penalty, and the exit-confirm dialog. Any
    // two of them can race (e.g. the timer expires right as the player
    // taps Exit). Only the first one through actually runs; a second call
    // is a no-op instead of double-saving the result and pushing a second
    // Result screen.
    if (_ended) return;
    _ended = true;

    timer?.cancel();

    // If the exit-confirm dialog is still open -- the round ended
    // naturally at almost the same moment the player pressed back --
    // dismiss it now rather than letting the navigation below land on top
    // of it. Navigator.pushReplacement only replaces the topmost route;
    // if that's the dialog rather than this quiz screen, the quiz screen
    // is left stranded underneath in the back stack.
    if (_exitDialogOpen && mounted) {
      Navigator.of(context, rootNavigator: true).pop(false);
    }

    await AdService.instance.maybeShowInterstitialAfterQuiz();

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder:
            (context) => ResultScreen(
              score: score,
              correct: correctAnswers,
              wrong: wrongAnswers,
              weakestCategory: getWeakestCategory(),
              missedQuestionIds: missedQuestionIds,
              completed: !exitedEarly,
              category: widget.category,
            ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    timerPulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      _handleReturnFromBackground();
    }
  }

  void _handleReturnFromBackground() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;

    if (backgroundedAt == null) return;
    if (!mounted || questions.isEmpty) return;
    // _exitDialogOpen matters here for the same reason it does in Rapid
    // Fire: with the "Exit this game?" dialog up, the player isn't
    // dodging the question, and penalising them would lose a life and
    // advance to a new question behind a modal barrier they can't see
    // past. This guard was added to Rapid Fire but originally missed
    // here, leaving the two modes inconsistent.
    if (isAnswered || _ended || _exitDialogOpen) return;

    final awayFor = DateTime.now().difference(backgroundedAt);
    if (awayFor < _backgroundGraceThreshold) return;

    _failCurrentQuestionForLeavingApp();
  }

  void _failCurrentQuestionForLeavingApp() {
    timer?.cancel();
    timerPulseController.stop();
    timerPulseController.value = 1.0;

    final currentCategory = questions[currentQuestionIndex].category;

    setState(() {
      isAnswered = true;
      selectedAnswer = null;
    });

    lives--;
    wrongAnswers++;
    // Counted here, not at round load -- this is the moment the question
    // was actually faced. See initState() for why.
    categoryTotal[currentCategory] = (categoryTotal[currentCategory] ?? 0) + 1;
    categoryWrong[currentCategory] = (categoryWrong[currentCategory] ?? 0) + 1;
    missedQuestionIds.add(questions[currentQuestionIndex].id);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Left the app during a question -- marked as wrong to keep results fair.",
        ),
        duration: Duration(seconds: 3),
      ),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      if (lives == 0) {
        AudioService.playSfx('gameover.wav');
        endQuiz();
        return;
      }
      nextQuestion();
    });
  }

  Color getOptionColor(int i, Question q) {
    if (!isAnswered) return const Color(0xFF232A36);

    if (i == q.correctIndex) return Colors.green;
    if (i == selectedAnswer) return Colors.red;
    return const Color(0xFF232A36);
  }

  // Backing out mid-game used to discard the round entirely -- which meant
  // a player about to lose their last life could just leave and keep their
  // stats clean, with zero cost. Now leaving early banks whatever the round
  // looks like at that exact moment (same as running out of lives) rather
  // than throwing it away, so there's no free do-over.
  Future<bool> _confirmExit() async {
    // Deliberately does NOT pause the question timer while this dialog is
    // up. An earlier version cancelled the timer here and resumed it on
    // "Keep Playing" -- but the question and options are still visible
    // behind the dialog, so that let a player freeze the clock indefinitely
    // (open the dialog, look up the answer with unlimited time, then Keep
    // Playing with a full 30 seconds still on it). The timer keeps
    // ticking normally instead; if it hits zero while this dialog is open,
    // endQuiz()'s _ended guard plus the dialog-dismiss logic there handle
    // that race safely.
    _exitDialogOpen = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF181C24),
            title: const Text(
              "Exit this game?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Your result so far will be saved as final -- leaving early "
              "isn't a do-over.",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Keep Playing"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Exit",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );

    _exitDialogOpen = false;
    final shouldExit = result ?? false;

    return shouldExit;
  }

  Future<void> _handleExitAttempt() async {
    final shouldExit = await _confirmExit();
    if (shouldExit && mounted) {
      await endQuiz(exitedEarly: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final q = questions[currentQuestionIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExitAttempt();
      },
      child: Scaffold(
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
      ),
    );
  }
}
