import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import '../models/question.dart';

class QuestionService {
  static List<Question> _allQuestions = [];
  static bool _loaded = false;

  static List<String> getPremiumCategories() {
    return [
      "Mixed",
      "Polity",
      "History",
      "Geography",
      "Science",
      "Current Affairs",
      "Defence",
      "Math",
      "Reasoning",
      "Static GK",
      "Technology",
    ];
  }

  static Future<void> loadQuestions() async {
    if (_loaded) return;

    final String jsonString = await rootBundle.loadString(
      'assets/data/questions.json',
    );

    final List<dynamic> jsonData = json.decode(jsonString);

    _allQuestions = jsonData.map((e) => Question.fromJson(e)).toList();
    _loaded = true;
  }

  static List<Question> _cloneShuffleAndFixOptions(List<Question> input) {
    final List<Question> result =
        input.map((q) {
          final copied = Question(
            id: q.id,
            category: q.category,
            subcategory: q.subcategory,
            difficulty: q.difficulty,
            question: q.question,
            options: List<String>.from(q.options),
            correctIndex: q.correctIndex,
          );

          final correctAnswer = copied.options[copied.correctIndex];
          copied.options.shuffle(Random());
          copied.correctIndex = copied.options.indexOf(correctAnswer);

          return copied;
        }).toList();

    result.shuffle(Random());
    return result;
  }

  static List<Question> getQuestionsForNormalMode({
    required bool isPremium,
    String selectedCategory = "Mixed",
    int count = 12,
  }) {
    if (!_loaded) return [];

    if (!isPremium || selectedCategory == "Mixed") {
      return _getMixedNormalQuestions(count: count);
    }

    List<Question> filtered =
        _allQuestions.where((q) => q.category == selectedCategory).toList();

    filtered = _cloneShuffleAndFixOptions(filtered);

    if (filtered.length <= count) return filtered;
    return filtered.take(count).toList();
  }

  static List<Question> _getMixedNormalQuestions({int count = 12}) {
    Map<String, int> blueprint = {
      "Current Affairs": 2,
      "History": 2,
      "Geography": 1,
      "Polity": 1,
      "Defence": 1,
      "Science": 1,
      "Reasoning": 1,
      "Math": 1,
      "Technology": 1,
      "Static GK": 1,
    };

    List<Question> picked = [];

    blueprint.forEach((category, needed) {
      List<Question> pool =
          _allQuestions.where((q) => q.category == category).toList();

      pool = _cloneShuffleAndFixOptions(pool);
      picked.addAll(pool.take(needed));
    });

    picked = _cloneShuffleAndFixOptions(picked);

    if (picked.length <= count) return picked;
    return picked.take(count).toList();
  }

  static List<Question> getQuestionsForRapidFire({int count = 20}) {
    if (!_loaded) return [];

    List<Question> fastPool = [];

    for (String category in [
      "Current Affairs",
      "Science",
      "Defence",
      "Reasoning",
      "Static GK",
      "Technology",
      "History",
      "Geography",
      "Polity",
      "Math",
    ]) {
      fastPool.addAll(_allQuestions.where((q) => q.category == category));
    }

    fastPool = _cloneShuffleAndFixOptions(fastPool);

    if (fastPool.length <= count) return fastPool;
    return fastPool.take(count).toList();
  }
}
