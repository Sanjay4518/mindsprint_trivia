import 'dart:async';
import 'package:flutter/material.dart';
import '../models/question.dart';
import '../services/question_service.dart';
import '../services/player_service.dart';
import '../services/player_repository.dart';
import '../services/audio_service.dart';
import 'home_screen.dart';

/// Practice Mode: built entirely from the player's own local "wrong
/// answers" history (see PlayerService.wrongQuestionIds). No backend, no
/// stamina cost, no timer -- this screen itself never gates anything.
///
/// Access to it IS gated for free players, deliberately, at the call site
/// (see HomeScreen.buildPracticeModeButton/_showPracticeLockedPrompt --
/// the same watch-ad/go-Premium bridge used for locked categories). That
/// used to be described here as something that "should never be gated,"
/// which no longer matched HomeScreen's actual, intentional behavior --
/// corrected 2026-09-04 so this comment doesn't contradict the real
/// product decision. This file's own mechanics (free, untimed, no
/// stamina cost) are unchanged; only the note about what happens before a
/// player reaches this screen was wrong.
///
/// Flow:
///  1. Review screen -- every missed question shown with its correct
///     answer, read-only, so the player studies before being quizzed.
///  2. Quiz screen -- untimed, one short session (see
///     PlayerService.practiceSessionSize) randomly drawn from the wrong
///     pool, no repeats within a session. A question needs to be answered
///     correctly across [PlayerService.masteryThreshold] SEPARATE sessions
///     (not in a row, not on demand) to be mastered; any wrong answer
///     resets that question's progress. Each question that appears also
///     goes on a short cooldown before it can be picked again, so the
///     rotation feels natural rather than grindable.
///  3. Session Complete screen -- shown once the session's questions have
///     all been answered once each. Offers another session if questions
///     remain in the pool.
class PracticeModeScreen extends StatefulWidget {
  const PracticeModeScreen({super.key});

  @override
  State<PracticeModeScreen> createState() => _PracticeModeScreenState();
}

enum _PracticeStage { loading, empty, review, quiz, complete }

class _PracticeModeScreenState extends State<PracticeModeScreen> {
  _PracticeStage stage = _PracticeStage.loading;

  List<Question> reviewQuestions = [];
  List<Question> sessionQuestions = [];
  int currentIndexInSession = -1;
  Question? currentQuestion;

  int? selectedAnswer;
  bool isAnswered = false;
  String feedbackText = "";
  Color feedbackColor = Colors.white70;

  int masteredThisSession = 0;
  int sessionCorrectCount = 0;
  int sessionWrongCount = 0;

  @override
  void initState() {
    super.initState();
    loadQuestions();
  }

  void loadQuestions() {
    final questions = QuestionService.getQuestionsForPracticeMode(
      List<String>.from(PlayerService.wrongQuestionIds),
      shuffleOrder: false,
    );

    setState(() {
      reviewQuestions = questions;
      stage = questions.isEmpty ? _PracticeStage.empty : _PracticeStage.review;
    });
  }

  // Guards against a double-tap on "Start Quiz". startPracticeSession()
  // advances the session counter and puts every question it draws on a
  // 3-4 session cooldown, so running it twice quietly burned through
  // twice the pool and degraded the rotation it exists to create.
  bool _startingQuiz = false;

  void startQuiz() async {
    if (_startingQuiz) return;
    _startingQuiz = true;

    try {
      final selectedIds = await PlayerService.startPracticeSession();

      // startPracticeSession() writes to SharedPreferences, so this is a
      // real await -- backing out of the screen during it would otherwise
      // reach a setState() after dispose(). No lint catches that.
      if (!mounted) return;

      if (selectedIds.isEmpty) {
        // Nothing left in the pool (can happen if everything got mastered
        // since this screen was opened) -- just re-check overall state.
        loadQuestions();
        return;
      }

      final questions = QuestionService.getQuestionsForPracticeMode(
        selectedIds,
        shuffleOrder: true,
      );

      _applyNewSession(questions);
    } finally {
      _startingQuiz = false;
    }
  }

  void _applyNewSession(List<Question> questions) {
    setState(() {
      sessionQuestions = questions;
      currentIndexInSession = -1;
      masteredThisSession = 0;
      sessionCorrectCount = 0;
      sessionWrongCount = 0;
      stage = _PracticeStage.quiz;
    });
    pickNextQuestion();
  }

  void pickNextQuestion() {
    final nextIndex = currentIndexInSession + 1;

    if (nextIndex >= sessionQuestions.length) {
      setState(() => stage = _PracticeStage.complete);
      // Practice Mode updates local state (savePlayer()) after every
      // answer via PlayerService.recordPracticeAnswer, but previously
      // never pushed any of it to the cloud itself -- syncCurrentPlayer()
      // only ever fired from other screens (a timed round result, the
      // Premium screen, a rename) or the next full cold start of the app.
      // A player who practices and then loses/reinstalls the app before
      // any of those happen would have their mastery progress sitting
      // locally, never backed up. Syncing once here, at the natural end
      // of a session (same pattern as every timed mode), closes that gap
      // without pushing on every single answer.
      unawaited(PlayerRepository.syncCurrentPlayer());
      return;
    }

    setState(() {
      currentIndexInSession = nextIndex;
      currentQuestion = sessionQuestions[nextIndex];
      selectedAnswer = null;
      isAnswered = false;
      feedbackText = "";
    });
  }

  void checkAnswer(int selectedIndex) async {
    if (isAnswered || currentQuestion == null) return;

    final q = currentQuestion!;
    final bool correct = selectedIndex == q.correctIndex;

    setState(() {
      selectedAnswer = selectedIndex;
      isAnswered = true;
    });

    final bool mastered = await PlayerService.recordPracticeAnswer(
      q.id,
      correct,
    );

    if (correct) {
      sessionCorrectCount++;
    } else {
      sessionWrongCount++;
    }

    if (mastered) {
      AudioService.playSfx('correct.wav');
      masteredThisSession++;
      feedbackText = "🎉 Mastered! Moved into your correct-answer stats.";
      feedbackColor = Colors.greenAccent;
    } else if (correct) {
      AudioService.playSfx('correct.wav');
      final streak = PlayerService.correctStreakFor(q.id);
      feedbackText =
          "✅ Correct — retained in $streak of ${PlayerService.masteryThreshold} sessions so far.";
      feedbackColor = Colors.greenAccent;
    } else {
      AudioService.playSfx('wrong.wav');
      feedbackText = "❌ Not quite — this resets progress on this question.";
      feedbackColor = Colors.redAccent;
    }

    if (mounted) setState(() {});

    Future.delayed(const Duration(milliseconds: 1100), () {
      if (!mounted) return;
      pickNextQuestion();
    });
  }

  Color getOptionColor(int i, Question q) {
    if (!isAnswered) return const Color(0xFF232A36);
    if (i == q.correctIndex) return Colors.green;
    if (i == selectedAnswer) return Colors.red;
    return const Color(0xFF232A36);
  }

  void goHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const HomeScreen()),
      (route) => false,
    );
  }

  Widget buildEmptyState() {
    return Scaffold(
      appBar: AppBar(title: const Text("Practice Mode")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.greenAccent,
                size: 64,
              ),
              const SizedBox(height: 18),
              const Text(
                "Nothing to practice right now",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Play Normal Mode or Rapid Fire, and any questions you get wrong will show up here automatically for review.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: goHome,
                  child: const Text("Back to Home"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildReviewCard(Question q) {
    final streak = PlayerService.correctStreakFor(q.id);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                q.category,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (streak > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    "$streak/${PlayerService.masteryThreshold} sessions retained",
                    style: const TextStyle(color: Colors.orange, fontSize: 11),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            q.question,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.check_circle_rounded,
                  color: Colors.greenAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    q.options[q.correctIndex],
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildReviewStage() {
    return Scaffold(
      appBar: AppBar(
        title: Text("Review • ${reviewQuestions.length} question(s)"),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF181C24),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: Text(
                  "Read through the questions you've gotten wrong and their correct answers below. Each practice quiz pulls a random ${PlayerService.practiceSessionSize} of these -- get a question right across ${PlayerService.masteryThreshold} separate sessions to master it for good.",
                  style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: reviewQuestions.length,
                itemBuilder: (context, i) => buildReviewCard(reviewQuestions[i]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: startQuiz,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text(
                "Start Quiz",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F8F4A),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildQuizStage() {
    final q = currentQuestion;
    if (q == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Practice Quiz • Question ${currentIndexInSession + 1} of ${sessionQuestions.length}",
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.replay_circle_filled_rounded,
                    color: Colors.greenAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "No timer, no stamina cost -- retain it across ${PlayerService.masteryThreshold} sessions to master",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
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
                      color: Colors.greenAccent,
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
            const SizedBox(height: 14),
            if (feedbackText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: feedbackColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: feedbackColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  feedbackText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: feedbackColor, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
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
          ],
        ),
      ),
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

  Widget buildCompleteStage() {
    final int remaining = PlayerService.wrongQuestionIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Session Complete"),
        automaticallyImplyLeading: false,
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
                    colors: [Color(0xFF164A2D), Color(0xFF1F8F4A)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Session Complete",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      masteredThisSession > 0
                          ? "$masteredThisSession mastered this session"
                          : "${sessionQuestions.length} question(s) practiced",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  buildStatCard("Correct", "$sessionCorrectCount", Colors.green),
                  const SizedBox(width: 12),
                  buildStatCard("Wrong", "$sessionWrongCount", Colors.redAccent),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  buildStatCard(
                    "Mastered",
                    "$masteredThisSession",
                    Colors.amber,
                  ),
                  const SizedBox(width: 12),
                  buildStatCard(
                    "Still practicing",
                    "$remaining",
                    Colors.orange,
                  ),
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
                  remaining > 0
                      ? "You've still got $remaining question(s) to master. They'll rotate back into your practice sessions naturally over the next few quizzes -- no need to grind them all right now."
                      : "You've mastered every question you've gotten wrong so far. Getting something wrong in a future game will bring it back here.",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (remaining > 0)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: startQuiz,
                    child: const Text("Practice Again"),
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
                  child: const Text("Back to Home"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case _PracticeStage.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _PracticeStage.empty:
        return buildEmptyState();
      case _PracticeStage.review:
        return buildReviewStage();
      case _PracticeStage.quiz:
        return buildQuizStage();
      case _PracticeStage.complete:
        return buildCompleteStage();
    }
  }
}
