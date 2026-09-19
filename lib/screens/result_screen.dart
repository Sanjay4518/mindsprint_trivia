import 'dart:async';
import 'package:flutter/material.dart';
import 'game_info_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import '../helpers/mode_entry_helper.dart';
import '../services/stamina_service.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../widgets/promotion_celebration_dialog.dart';
import '../widgets/sign_in_protect_prompt_dialog.dart';

class ResultScreen extends StatefulWidget {
  final int score;
  final int correct;
  final int wrong;
  final String weakestCategory;
  final List<String> missedQuestionIds;

  // The category this round was actually played in ("Mixed" for free
  // players, or whichever category a Premium player chose). Play Again
  // uses this so a Premium player replaying e.g. Polity isn't silently
  // bumped to a Mixed quiz -- see playAgain() below.
  final String category;

  // True for a real game-over (ran out of lives, or answered every
  // question) -- false when the player backed out early via the
  // exit-confirmation prompt. Gates the accuracy bonus and stamina
  // refund/refill below: without this, exiting right after one lucky
  // correct answer could bank a "100% accuracy" partial result and farm
  // free XP plus a full stamina refill, over and over. See
  // NormalModeScreen._handleExitAttempt.
  final bool completed;

  const ResultScreen({
    super.key,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.weakestCategory,
    required this.completed,
    required this.category,
    this.missedQuestionIds = const [],
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

    if (!widget.completed) {
      // Backed out early -- the round is still banked as final (correct/
      // wrong stats and the raw score below are saved either way, so
      // quitting never wipes out real progress), but it deliberately does
      // NOT unlock the completion bonus or the stamina refund/refill.
      // Those exist to reward finishing a full round, not bailing out
      // right after a lucky start.
      xpBonus = 0;
      rewardText = "Exited early -- no completion bonus this round.";
    } else if (accuracy == 100) {
      // Bonus tiers rebalanced 2026-09-10, per Sanjay's explicit target:
      // a player consistently landing in the 50-70% accuracy band should
      // take about 5-6 Normal Mode rounds to go from Bronze to Silver, and
      // each subsequent league should take noticeably longer than the
      // last (see the widened gaps in LeagueService.leagues, changed in
      // the same pass). The old flat +500/+500/+300/+200/+100 tiers made
      // even a mediocre round pay almost as well as a flawless one, so the
      // early leagues cleared in just 3-5 rounds regardless of real skill
      // -- confirmed against a real account (6 rounds, 66.7% accuracy,
      // already past Gold). These smaller, more spread-out tiers keep
      // rewarding real mastery without changing anything about how a
      // single question is scored (+20 XP correct, same as before).
      xpBonus = 200;
      rewardText = "🔥 Perfect! Full stamina restored!";
      StaminaService.currentStamina = StaminaService.maxStamina;
    } else if (accuracy >= 90) {
      xpBonus = 150;
      rewardText = "⚡ Excellent! Stamina refunded!";
      StaminaService.currentStamina += StaminaService.lastUsedStamina;
    } else if (accuracy >= 70) {
      xpBonus = 100;
      rewardText = "💪 Great performance!";
    } else if (accuracy >= 50) {
      xpBonus = 50;
      rewardText = "👍 Good job!";
    } else if (accuracy >= 40) {
      xpBonus = 25;
      rewardText = "📈 Keep improving!";
    }

    if (StaminaService.currentStamina > StaminaService.maxStamina) {
      StaminaService.currentStamina = StaminaService.maxStamina;
    }

    totalXpEarned = widget.score + xpBonus;
    badge = PlayerService.getPerformanceBadge(accuracy);
    message = PlayerService.getPerformanceMessage(accuracy);

    if (!saved) {
      // loadPlayer() is wrapped on purpose: this is the one call site
      // where letting a SharedPreferences hiccup throw would abort the
      // whole method before recordNormalResult ever runs, silently
      // discarding a round the player just finished. The in-memory
      // PlayerService values are still usable if the reload fails, so
      // recording the result is strictly better than bailing out.
      try {
        await PlayerService.loadPlayer();
      } catch (e) {
        debugPrint('ResultScreen: loadPlayer failed, saving anyway: $e');
      }
      await PlayerService.recordNormalResult(
        xpEarned: totalXpEarned,
        correct: widget.correct,
        wrong: widget.wrong,
        wrongQuestionIds: widget.missedQuestionIds,
      );
      await StaminaService.saveStamina();
      saved = true;
      unawaited(PlayerRepository.syncCurrentPlayer());
    }

    if (mounted) {
      setState(() {});
    }

    // Checked last, after the result is fully saved and the screen has
    // already rendered the normal result -- a promotion celebration is a
    // bonus on top of the result screen, never a replacement for it, and
    // showIfPending() is a no-op whenever recordNormalResult() above
    // didn't actually cross a league boundary.
    if (mounted) {
      final justPromoted = await PromotionCelebrationDialog.showIfPending(
        context,
      );
      // Chained right after (not simultaneously) -- see
      // SignInProtectPromptDialog's own doc comment for exactly which
      // moments trigger it. A no-op for anyone already signed in, or when
      // neither the promotion nor the game-15 backoff trigger applies yet.
      if (mounted) {
        final wantsSignIn = await SignInProtectPromptDialog.maybeShow(
          context,
          justPromoted: justPromoted,
        );
        if (wantsSignIn && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ProfileScreen()),
          );
        }
      }
    }
  }

  Color getBadgeColor() {
    if (accuracy >= 90) return Colors.green;
    if (accuracy >= 70) return Colors.blue;
    if (accuracy >= 50) return Colors.orange;
    return Colors.redAccent;
  }

  // Opens the same full Game Info screen used elsewhere in the app (see
  // game_info_screen.dart) instead of a small scoring-only dialog -- right
  // after a round is exactly when a player is most likely to wonder "how
  // did this number happen", so this gives them the complete picture
  // (scoring, accuracy bonuses, stamina, everything) rather than a partial
  // one, and there's only one place to keep this content correct.
  void showInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GameInfoScreen()),
    );
  }

  void playAgain() async {
    // Routed through ModeEntryHelper instead of spending stamina and
    // navigating directly (as this used to) -- that bypassed the
    // server-time sync before the stamina gate, the low-stamina popup
    // (watch ad / go Premium) when stamina is short, and silently dropped
    // whatever category a Premium player had actually chosen in favor of
    // always restarting as "Mixed". This uses the real category the round
    // was played in, and the normal stamina cost from ModeEntryHelper
    // rather than a separately hardcoded value.
    await ModeEntryHelper.startNormalModeForCategory(context, widget.category);
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
            // "None" means a flawless round -- see
            // NormalModeScreen.getWeakestCategory. Telling someone who
            // just scored 100% that they have a weak area reads as broken,
            // so the upsell makes the positive case instead.
            widget.weakestCategory == "None"
                ? "Perfect round -- nothing missed. Premium unlocks focused practice by category, plus the ability to review and re-practice every question you've gotten wrong until you've truly mastered it."
                : "Your weakest area is ${widget.weakestCategory}. Premium unlocks focused practice by category, plus the ability to review and re-practice every question you've gotten wrong until you've truly mastered it.",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Android's back button used to pop straight into whatever sits below
    // this screen. "Play Again" pushes a fresh round without removing this
    // result screen, and that round then replaces itself with another
    // result screen -- so after a few replays, back landed the player on a
    // previous round's result, showing stale numbers with a live "Play
    // Again" button on it. The back arrow is already hidden here
    // (automaticallyImplyLeading: false); this makes the hardware button
    // agree with that, and sends them Home instead, which is where the
    // only other button on this screen goes anyway.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        goHome();
      },
      child: buildResultScaffold(),
    );
  }

  Widget buildResultScaffold() {
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
                      "$totalXpEarned XP",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (xpBonus > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        "${widget.score} for questions answered + "
                        "$xpBonus bonus",
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                        ),
                      ),
                    ],
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
                  widget.weakestCategory == "None"
                      ? "Weakest Category: none — perfect round!"
                      : "Weakest Category: ${widget.weakestCategory}",
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
