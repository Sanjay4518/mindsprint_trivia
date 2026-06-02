import 'package:flutter/material.dart';
import '../services/player_service.dart';
import '../services/question_service.dart';
import 'normal_mode_screen.dart';

class CategorySelectScreen extends StatelessWidget {
  const CategorySelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories = QuestionService.getPremiumCategories();

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
                "Choose a topic and sharpen one area at a time.",
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (!PlayerService.isPremium)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    "Category-based quizzes are premium only. Upgrade later to unlock focused practice.",
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final locked =
                        !PlayerService.isPremium && category != "Mixed";

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              locked
                                  ? const Color(0xFF2A2F3A)
                                  : const Color(0xFF181C24),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 60),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                        ),
                        onPressed: () {
                          if (locked) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Premium required for category mode",
                                ),
                              ),
                            );
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder:
                                  (context) =>
                                      NormalModeScreen(category: category),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Icon(
                              locked ? Icons.lock_rounded : Icons.topic_rounded,
                              size: 20,
                              color:
                                  locked
                                      ? Colors.white38
                                      : Colors.lightBlueAccent,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              category,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (locked) ...[
                              const Spacer(),
                              const Icon(
                                Icons.workspace_premium_rounded,
                                size: 18,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
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
