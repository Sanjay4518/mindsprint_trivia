class Question {
  final String id;
  final String category;
  final String subcategory;
  final String difficulty;
  final String question;
  final List<String> options;
  int correctIndex;

  Question({
    required this.id,
    required this.category,
    required this.subcategory,
    required this.difficulty,
    required this.question,
    required this.options,
    required this.correctIndex,
  });

  factory Question.fromJson(Map<String, dynamic> json) {
    return Question(
      id: json['id'],
      category: json['category'],
      subcategory: json['subcategory'],
      difficulty: json['difficulty'],
      question: json['question'],
      options: List<String>.from(json['options']),
      correctIndex: json['correctIndex'],
    );
  }
}
