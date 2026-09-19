import 'dart:async';
import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/question_service.dart';
import '../services/stamina_service.dart';
import '../services/audio_service.dart';
import '../services/player_service.dart';
import '../services/ad_service.dart';
import 'rapid_fire_result_screen.dart';

class RapidFireScreen extends StatefulWidget {
  // Rapid Fire always draws from all 10 categories (see
  // QuestionService.getQuestionsForRapidFire) -- there was previously a
  // `category` constructor parameter here that nothing in this class ever
  // actually read (questions are always Mixed, the AppBar title is always
  // hardcoded to "Rapid Fire • Mixed"), which invited a future caller to
  // wrongly assume passing a different category would work. Removed as
  // dead code; the only call site (ModeEntryHelper) always passed "Mixed"
  // anyway.
  const RapidFireScreen({super.key});

  @override
  State<RapidFireScreen> createState() => _RapidFireScreenState();
}

class _RapidFireScreenState extends State<RapidFireScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // Guards endQuiz() against running twice -- e.g. the round timer hitting
  // zero at almost the same moment the player confirms Exit. Without
  // this, both paths could save the result and navigate, double-counting
  // XP/stats. See endQuiz().
  bool _ended = false;

  // True while the exit-confirmation dialog is on screen -- lets endQuiz()
  // know to dismiss it before navigating, so a naturally-timed game-over
  // (timer hits 0) that fires while the player is still deciding doesn't
  // leave the dialog's route in an inconsistent state.
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
    loadQuestions();

    timerPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
      lowerBound: 0.95,
      upperBound: 1.05,
    );

    if (questions.isNotEmpty) {
      startTimer();
    }
  }

  void loadQuestions() {
    questions = QuestionService.getQuestionsForRapidFire(count: 20);

    // Deliberately does NOT clear categoryTotal/categoryWrong -- this
    // method also runs mid-round (see nextQuestion()) every time the
    // player exhausts one 20-question batch and the next one loads, which
    // happens routinely within a single 90-second round. Clearing here
    // used to wipe out every earlier batch's tally each time a new one
    // loaded, so getWeakestCategory() at the end of the round only ever
    // reflected the *last* batch the player saw, not the whole round.
    // These maps only need to start empty once per round, which they
    // already do (fresh instance fields on a fresh State) -- from then on
    // each new batch should only ever add to the running totals.
    //
    // categoryTotal is deliberately NOT populated here any more. Rapid
    // Fire loads questions in batches of 20 but the player only ever
    // faces as many as the 90-second clock allows, so counting a whole
    // batch at load time treated every unseen question as answered
    // correctly (getWeakestCategory derives correct as total - wrong).
    // A player who missed 3 Reasoning questions out of the 5 they
    // actually saw could still show Reasoning at 85% because 15 unseen
    // ones were silently counted in their favour. Each question is now
    // counted at the moment it's actually faced -- see checkAnswer and
    // _failCurrentQuestionForLeavingApp.
  }

  void startTimer() {
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
    if (isAnswered || questions.isEmpty || _ended) return;

    setState(() {
      selectedAnswer = selectedIndex;
      isAnswered = true;
    });

    final currentQuestion = questions[currentQuestionIndex];
    final currentCategory = currentQuestion.category;

    // Counted here, not at batch load -- this is the moment the question
    // was actually faced. See loadQuestions() for why.
    categoryTotal[currentCategory] = (categoryTotal[currentCategory] ?? 0) + 1;

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
      missedQuestionIds.add(currentQuestion.id);
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
    if (questions.isEmpty || _ended) return;

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
    // Same guard as NormalModeScreen.getWeakestCategory: with only one
    // category actually faced, naming it "weakest" is misleading rather
    // than informative -- there's nothing else to compare it against.
    // Rapid Fire always samples across all 10 categories, so this is a
    // rare edge case here (a round ending after only a couple of
    // questions, all from the same category by chance) rather than the
    // routine case it is for a Premium category-specific Normal Mode
    // round -- but the same reasoning applies whenever it happens.
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

    // Flawless round -- every category sits at 100%, so naming one would
    // just be whichever happened to come first. See the identical guard
    // in NormalModeScreen.getWeakestCategory.
    if (worstAccuracy >= 100) return "None";

    return weakest;
  }

  Future<void> endQuiz() async {
    // Several different paths can reach endQuiz() -- the round timer
    // hitting zero, the backgrounding penalty, and the exit-confirm
    // dialog. Any two of them can race (e.g. the timer expires right as
    // the player taps Exit). Only the first one through actually runs; a
    // second call is a no-op instead of double-saving the result and
    // pushing a second Result screen.
    if (_ended) return;
    _ended = true;

    timer?.cancel();
    timerPulseController.stop();
    timerPulseController.value = 1.0;
    AudioService.playSfx('complete.wav');

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
            (context) => RapidFireResultScreen(
              score: score,
              correct: correctAnswers,
              wrong: wrongAnswers,
              bestStreak: bestStreak,
              weakestCategory: getWeakestCategory(),
              missedQuestionIds: missedQuestionIds,
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
    // Also skip the penalty while the exit-confirm dialog is open. Without
    // this, a player who presses back mid-question (opening "Exit this
    // round?") and then gets legitimately interrupted -- a phone call,
    // screen lock/timeout, anything that backgrounds the app while they're
    // still deciding -- comes back to find their current question auto-
    // marked wrong, even though they weren't sneaking off to look up an
    // answer. There's nothing to protect against here either way: if they
    // do choose Exit, the round gets banked as-is regardless.
    if (isAnswered || _ended || _exitDialogOpen) return;

    final awayFor = DateTime.now().difference(backgroundedAt);
    if (awayFor < _backgroundGraceThreshold) return;

    _failCurrentQuestionForLeavingApp();
  }

  void _failCurrentQuestionForLeavingApp() {
    final currentQuestion = questions[currentQuestionIndex];
    final currentCategory = currentQuestion.category;

    setState(() {
      selectedAnswer = null;
      isAnswered = true;
    });

    streak = 0;
    score -= 15;
    wrongAnswers++;
    // Faced and failed, so it counts toward this category's total too --
    // same reasoning as checkAnswer, see loadQuestions().
    categoryTotal[currentCategory] = (categoryTotal[currentCategory] ?? 0) + 1;
    categoryWrong[currentCategory] = (categoryWrong[currentCategory] ?? 0) + 1;
    missedQuestionIds.add(currentQuestion.id);
    AudioService.playSfx('wrong.wav');
    showXpPopup("-15");

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Left the app during a question -- marked as wrong to keep results fair.",
        ),
        duration: Duration(seconds: 3),
      ),
    );

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (totalTimeLeft > 0) {
        nextQuestion();
      }
    });
  }

  // Backing out mid-round used to discard the round entirely -- which meant
  // a player watching their score go negative could just leave and dodge
  // the hit, with zero cost. Now leaving early banks whatever the round
  // looks like at that exact moment (same as the timer running out) rather
  // than throwing it away, so there's no free do-over on a bad round.
  Future<bool> _confirmExit() async {
    // Deliberately does NOT pause the round timer while this dialog is up.
    // An earlier version cancelled the timer here and resumed it on "Keep
    // Playing" -- but the question and options are still visible behind
    // the dialog, so that let a player freeze the clock indefinitely (open
    // the dialog, look up the answer with unlimited time, then Keep
    // Playing with the clock untouched). The timer keeps ticking normally
    // instead; if it hits zero while this dialog is open, endQuiz()'s
    // _ended guard plus the dialog-dismiss logic there handle that race
    // safely.
    _exitDialogOpen = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => AlertDialog(
            backgroundColor: const Color(0xFF181C24),
            title: const Text(
              "Exit this round?",
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              "Your current score will be saved as final -- leaving early "
              "isn't a do-over, even if you're in the negative.",
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
      await endQuiz();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          await _handleExitAttempt();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text("Rapid Fire")),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final q = questions[currentQuestionIndex];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExitAttempt();
      },
      child: Scaffold(
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
      ),
    );
  }
}
