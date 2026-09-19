class Question {
  final String id;
  final String category;
  final String subcategory;
  final String difficulty;
  final String question;
  final List<String> options;
  final int correctIndex;

  Question({
    required this.id,
    required this.category,
    required this.subcategory,
    required this.difficulty,
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  /// Validates and parses one question record, returning null instead of
  /// throwing for anything malformed. Replaces the old unchecked
  /// `Question.fromJson` factory (removed 2026-09-02) -- that version did
  /// an implicit cast on every field, so a single missing/wrong-typed
  /// field or an out-of-range `correctIndex` anywhere in the ~2,138-entry
  /// question bank threw during `json.decode(...).map(...)` and made the
  /// whole app run with ZERO questions (every mode stuck on a permanent
  /// spinner) until the next store update. Skipping one bad row instead of
  /// losing the entire file is a much safer failure mode, especially
  /// since the question bank gets hand-edited (Phase B content cleanup).
  static Question? tryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final category = json['category'];
    final subcategory = json['subcategory'];
    final difficulty = json['difficulty'];
    final question = json['question'];
    final rawOptions = json['options'];
    final correctIndex = json['correctIndex'];

    if (id is! String || id.trim().isEmpty) return null;
    if (category is! String || category.trim().isEmpty) return null;
    if (subcategory is! String || subcategory.trim().isEmpty) return null;
    // Matches the schema's allowed difficulty values exactly (see the
    // project's content-cleanup docs) -- previously only type-checked, so
    // an empty string or a typo'd value (a real risk given the question
    // bank is hand-edited) loaded successfully and just silently never
    // matched any difficulty-specific filter, with no error surfaced
    // anywhere.
    if (difficulty is! String ||
        !const {'easy', 'medium', 'hard'}.contains(difficulty)) {
      return null;
    }
    if (question is! String || question.trim().isEmpty) return null;
    if (rawOptions is! List) return null;

    final options = rawOptions.whereType<String>().toList();
    // Exactly 4 options, and every one of them a real string -- if any
    // entry wasn't a string, options.length will be shorter than
    // rawOptions.length and this catches it too.
    if (options.length != rawOptions.length || options.length != 4) {
      return null;
    }

    if (correctIndex is! int ||
        correctIndex < 0 ||
        correctIndex >= options.length) {
      return null;
    }

    return Question(
      id: id,
      category: category,
      subcategory: subcategory,
      difficulty: difficulty,
      question: question,
      options: options,
      correctIndex: correctIndex,
    );
  }
}
