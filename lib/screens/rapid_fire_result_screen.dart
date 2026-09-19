import 'dart:async';
import 'package:flutter/material.dart';
import 'game_info_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import '../helpers/mode_entry_helper.dart';
import '../services/player_repository.dart';
import '../services/player_service.dart';
import '../widgets/promotion_celebration_dialog.dart';
import '../widgets/sign_in_protect_prompt_dialog.dart';

class RapidFireResultScreen extends StatefulWidget {
  final int score;
  final int correct;
  final int wrong;
  final int bestStreak;
  final String weakestCategory;
  final List<String> missedQuestionIds;

  const RapidFireResultScreen({
    super.key,
    required this.score,
    required this.correct,
    required this.wrong,
    required this.bestStreak,
    required this.weakestCategory,
    this.missedQuestionIds = const [],
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
      // Wrapped for the same reason as ResultScreen.calculateAndSave: a
      // failing reload must not abort this method before the round is
      // actually recorded.
      try {
        await PlayerService.loadPlayer();
      } catch (e) {
        debugPrint(
          'RapidFireResultScreen: loadPlayer failed, saving anyway: $e',
        );
      }
      // High-risk/high-reward: pass the real (possibly negative) round
      // score through -- PlayerService.recordRapidFireResult is what
      // floors the player's lifetime total at 0, not this screen.
      await PlayerService.recordRapidFireResult(
        xpEarned: widget.score,
        score: widget.score,
        correct: widget.correct,
        wrong: widget.wrong,
        wrongQuestionIds: widget.missedQuestionIds,
      );
      saved = true;
      unawaited(PlayerRepository.syncCurrentPlayer());
    }

    if (mounted) {
      setState(() {});
    }

    // See ResultScreen.calculateAndSave's identical call -- a no-op
    // whenever recordRapidFireResult() above didn't actually cross a
    // league boundary.
    if (mounted) {
      final justPromoted = await PromotionCelebrationDialog.showIfPending(
        context,
      );
      // See ResultScreen.calculateAndSave's identical chain -- a no-op for
      // anyone already signed in, or when neither trigger applies yet.
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

  // Opens the same full Game Info screen used elsewhere in the app (see
  // game_info_screen.dart, and result_screen.dart's identical treatment)
  // instead of a Rapid-Fire-only scoring dialog -- keeps Rapid Fire's
  // rules exactly as they are, just gives players the same complete
  // picture Normal Mode's result screen now does, from one place.
  void showInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GameInfoScreen()),
    );
  }

  void playAgain() async {
    // Routed through ModeEntryHelper instead of spending stamina and
    // navigating directly (as this used to) -- that bypassed the
    // server-time sync before the stamina gate and the low-stamina popup
    // (watch ad / go Premium) when stamina is short, and used a separately
    // hardcoded stamina cost instead of ModeEntryHelper.rapidCost. Rapid
    // Fire is always "Mixed" either way, so there's no category to
    // preserve here (unlike Normal Mode's Play Again -- see
    // result_screen.dart).
    await ModeEntryHelper.openRapidMode(context);
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
            // "None" means a flawless round -- see
            // RapidFireScreen.getWeakestCategory.
            widget.weakestCategory == "None"
                ? "Flawless round -- nothing missed. Premium unlocks focused practice by category, plus the ability to review and re-practice every question you've gotten wrong until you've truly mastered it."
                : "Your weakest category was ${widget.weakestCategory}. Premium unlocks focused practice by category, plus the ability to review and re-practice every question you've gotten wrong until you've truly mastered it.",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Same reasoning as ResultScreen: the back arrow is hidden, so the
    // hardware back button shouldn't drop the player onto a stale result
    // screen left behind by an earlier "Play Again."
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
    // "XP Saved" is framed as a gain, so it shouldn't ever show a negative
    // number -- "Final Score" above already shows the honest raw score
    // (which legitimately can be negative on a rough round); this is just
    // the floor for this one relabeled stat card, not a change to actual
    // recorded XP (recordRapidFireResult above still gets the real score).
    final savedXp = widget.score < 0 ? 0 : widget.score;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Rapid Fire Result"),
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
                  widget.weakestCategory == "None"
                      ? "Weakest Category: none — flawless round!"
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
