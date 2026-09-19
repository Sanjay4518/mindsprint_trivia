import 'package:flutter/material.dart';
import '../helpers/mode_entry_helper.dart';
import '../services/player_service.dart';
import '../services/question_service.dart';

class CategorySelectScreen extends StatefulWidget {
  const CategorySelectScreen({super.key});

  @override
  State<CategorySelectScreen> createState() => _CategorySelectScreenState();
}

class _CategorySelectScreenState extends State<CategorySelectScreen> {
  static const Map<String, IconData> _categoryIcons = {
    "Polity": Icons.account_balance_rounded,
    "History": Icons.history_edu_rounded,
    "Geography": Icons.public_rounded,
    "Science": Icons.science_rounded,
    "Current Affairs": Icons.newspaper_rounded,
    "Defence": Icons.shield_rounded,
    "Math": Icons.calculate_rounded,
    "Reasoning": Icons.psychology_rounded,
    "Static GK": Icons.lightbulb_rounded,
    "Technology": Icons.memory_rounded,
  };

  static const Map<String, Color> _categoryColors = {
    "Polity": Color(0xFF7C8CFF),
    "History": Color(0xFFD9A05B),
    "Geography": Color(0xFF4DD0C4),
    "Science": Color(0xFF7ED957),
    "Current Affairs": Color(0xFFFF8A3D),
    "Defence": Color(0xFF9DB4C0),
    "Math": Color(0xFFC084FC),
    "Reasoning": Color(0xFFFF6FA5),
    "Static GK": Color(0xFFFFD166),
    "Technology": Color(0xFF4FD1FF),
  };

  Widget _buildMixedCard(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => ModeEntryHelper.startNormalModeForCategory(context, "Mixed"),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4F8CFF), Color(0xFF2F6FE0)],
          ),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F8CFF).withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.shuffle_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Mixed",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    "A shuffled set from every category. Always free to play.",
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white70,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String category, bool locked) {
    final icon = _categoryIcons[category] ?? Icons.topic_rounded;
    final color = _categoryColors[category] ?? Colors.lightBlueAccent;

    return Opacity(
      opacity: locked ? 0.55 : 1.0,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap:
            locked
                ? () => _showLockedCategoryPrompt(context, category)
                : () => ModeEntryHelper.startNormalModeForCategory(
                  context,
                  category,
                ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF181C24),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: locked ? Colors.white10 : color.withValues(alpha: 0.35),
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: (locked ? Colors.white24 : color).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      icon,
                      color: locked ? Colors.white38 : color,
                      size: 21,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    category,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: locked ? Colors.white54 : Colors.white,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
              if (locked)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.lock_rounded,
                    color: Colors.white38,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showLockedCategoryPrompt(
    BuildContext context,
    String category,
  ) async {
    final bool? watchAd = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              "$category is Premium",
              style: const TextStyle(color: Colors.white),
            ),
            content: const Text(
              "This topic is locked for free players. Watch a short ad to "
              "unlock every category for 15 minutes, or go Premium for "
              "unlimited access.",
              style: TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Not now"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Watch Ad"),
              ),
            ],
          ),
    );

    if (watchAd != true || !context.mounted) return;

    final bool success = await ModeEntryHelper.tryWatchAdForTemporaryPremium(
      context,
    );

    if (success && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = QuestionService.getPremiumCategories();
    final topicCategories = categories.where((c) => c != "Mixed").toList();
    final bool isPremium = PlayerService.isPremium;

    return Scaffold(
      appBar: AppBar(title: const Text("Choose Category")),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Focused Practice",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Pick Mixed for a shuffled set, or unlock a single topic with Premium.",
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 18),
              _buildMixedCard(context),
              if (!isPremium) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    "Focused topics below are locked for free players. Upgrade to Premium to unlock every category.",
                    style: TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                "Focused Topics",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  itemCount: topicCategories.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.25,
                      ),
                  itemBuilder: (context, index) {
                    final category = topicCategories[index];
                    return _buildCategoryCard(context, category, !isPremium);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
