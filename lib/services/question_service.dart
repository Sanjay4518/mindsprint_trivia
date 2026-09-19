import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/question.dart';
import 'question_repository.dart';

class QuestionService {
  static List<Question> _allQuestions = [];
  static bool _loaded = false;

  // Hoisted to a single shared instance instead of constructing a new
  // Random() on every shuffle call -- cheap fix, slightly better
  // distribution than many short-lived generators.
  static final Random _random = Random();

  // A remote question bank with fewer than this many valid questions is
  // treated as broken rather than real content -- an empty or truncated
  // upload to Firebase Storage (see QuestionRepository) shouldn't be able
  // to take the whole question bank down app-wide for every player. Well
  // below the ~2,100 questions the bank actually has today, but high
  // enough that a genuinely empty/garbage file can't sneak past it.
  static const int _minSaneRemoteQuestionCount = 100;

  // Every category the app's fixed, hard-coded flows depend on --
  // getPremiumCategories() below, _getMixedNormalQuestions()'s blueprint,
  // and getQuestionsForRapidFire()'s category list. A question's own
  // `category` string is free-text (Question.tryFromJson only checks it's
  // a non-empty String, not that it's one of these), so a remote content
  // edit that renames or mistypes a category -- entirely plausible during
  // Phase B content cleanup, published straight to Storage with no build
  // step to catch it -- wouldn't fail any check so far, yet would leave
  // that category (or, for "Mixed", every free player's Normal Mode)
  // silently empty app-wide. See _hasHealthyCategoryCoverage below.
  static const List<String> _requiredCategories = [
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

  // Deliberately low -- this is a "did every category this app hard-codes
  // survive the upload at all" sanity check, not a content-quality bar.
  // The Mixed-mode blueprint only ever needs 1-2 questions per category
  // for a single round; this leaves generous headroom above that.
  static const int _minQuestionsPerCategory = 5;

  /// True only if every category the app's fixed flows depend on has at
  /// least [_minQuestionsPerCategory] valid questions. A remote question
  /// bank that fails this is treated the same as "too small to trust" --
  /// see [loadQuestions] -- and the app falls back to the bundled asset,
  /// which is always internally consistent with these exact category
  /// names since it's the one copy that's actually been reviewed.
  static bool _hasHealthyCategoryCoverage(List<Question> questions) {
    final counts = <String, int>{};
    for (final q in questions) {
      counts[q.category] = (counts[q.category] ?? 0) + 1;
    }
    for (final category in _requiredCategories) {
      if ((counts[category] ?? 0) < _minQuestionsPerCategory) return false;
    }
    return true;
  }

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

  /// Tries the remote question bank (Firebase Storage, via
  /// [QuestionRepository]) first, so content edits published there reach
  /// players without a new app build/release -- falls back to the copy
  /// bundled into the app whenever the remote one isn't usable for any
  /// reason (offline, nothing uploaded yet, a corrupt/too-small file).
  /// Parses each record independently and skips anything malformed rather
  /// than throwing, either way -- see [Question.tryFromJson].
  static Future<void> loadQuestions() async {
    if (_loaded) return;

    List<Question> parsed = [];
    try {
      final remoteJsonString = await QuestionRepository.loadJsonString();
      if (remoteJsonString != null) {
        final remoteData = json.decode(remoteJsonString) as List<dynamic>;
        final remoteParsed =
            remoteData
                .map((e) => Question.tryFromJson(e as Map<String, dynamic>))
                .whereType<Question>()
                .toList();
        if (remoteParsed.length >= _minSaneRemoteQuestionCount &&
            _hasHealthyCategoryCoverage(remoteParsed)) {
          parsed = remoteParsed;
        } else if (remoteParsed.length >= _minSaneRemoteQuestionCount) {
          // Enough questions overall, but at least one category the app
          // depends on is missing/under-represented -- most likely a
          // renamed or mistyped category string in a content edit. Logged
          // so this is discoverable (e.g. via `adb logcat`) rather than
          // just quietly serving the bundled asset with no explanation.
          debugPrint(
            'QuestionService: remote question bank rejected -- missing or '
            'under-represented category coverage (needs at least '
            '$_minQuestionsPerCategory questions in each of '
            '$_requiredCategories). Falling back to the bundled asset.',
          );
        }
        // else: too small to trust (likely an empty/broken upload) --
        // falls through to the bundled asset below instead.
      }
    } catch (_) {
      // Ignored on purpose -- malformed JSON from a bad upload, a Storage
      // hiccup that slipped past QuestionRepository, etc. Falls through to
      // the bundled asset below either way.
    }

    if (parsed.isEmpty) {
      // This is the last-resort fallback -- there's nowhere further to fall
      // back to, so a parse failure here still has to surface (the app has
      // no questions to show either way). The try/catch adds a clear,
      // discoverable log line before rethrowing, instead of letting a bad
      // edit to the bundled questions.json (e.g. from Phase B/C content
      // cleanup) surface as a bare, hard-to-diagnose exception with no
      // indication of which file or step failed.
      try {
        final String jsonString = await rootBundle.loadString(
          'assets/data/questions.json',
        );
        final List<dynamic> jsonData = json.decode(jsonString);
        parsed =
            jsonData
                .map((e) => Question.tryFromJson(e as Map<String, dynamic>))
                .whereType<Question>()
                .toList();
      } catch (e) {
        debugPrint(
          'QuestionService: failed to load bundled assets/data/questions.json '
          '-- $e',
        );
        rethrow;
      }
    }

    _allQuestions = parsed;
    _loaded = true;
  }

  /// Picks up to [count] random questions from [pool], then clones and
  /// option-shuffles only those, instead of transforming the whole pool
  /// and discarding nearly all of it.
  ///
  /// [_cloneShuffleAndFixOptions] allocates a new Question plus several
  /// lists per entry, so putting the entire ~2,100-question bank through
  /// it to obtain 20 questions is well over ten thousand allocations.
  /// Rapid Fire did exactly that mid-round, synchronously on the UI
  /// thread, every time a fast player exhausted a 20-question batch
  /// inside the 90-second clock -- a visible freeze during a timed mode
  /// on a slower phone. Sampling first makes the cost proportional to
  /// what's actually used.
  static List<Question> _sampleCloneAndFixOptions(
    List<Question> pool,
    int count,
  ) {
    if (pool.length <= count) return _cloneShuffleAndFixOptions(pool);

    // Partial Fisher-Yates over an index list -- touches `count` entries
    // instead of shuffling the whole pool.
    final indices = List<int>.generate(pool.length, (i) => i);
    final picked = <Question>[];
    for (int i = 0; i < count; i++) {
      final swapWith = i + _random.nextInt(indices.length - i);
      final int tmp = indices[i];
      indices[i] = indices[swapWith];
      indices[swapWith] = tmp;
      picked.add(pool[indices[i]]);
    }

    return _cloneShuffleAndFixOptions(picked);
  }

  static List<Question> _cloneShuffleAndFixOptions(List<Question> input) {
    final List<Question> result =
        input
            .map((q) {
              final correctOriginalIndex = q.correctIndex;
              if (correctOriginalIndex < 0 ||
                  correctOriginalIndex >= q.options.length) {
                // Shouldn't happen now that Question.tryFromJson validates
                // this at load time, but stays defensive rather than
                // throwing mid-quiz if it ever does.
                return null;
              }

              // Shuffles (original index -> option text) pairs, then finds
              // the correct answer by tracking which pair started at
              // correctOriginalIndex -- NOT by searching for matching text.
              // The old version re-found the correct answer with
              // `options.indexOf(correctAnswer)` after shuffling, which
              // returns the FIRST matching option text. For the questions
              // with duplicate option text (see the content audit -- e.g.
              // rea_002, mat_070), that could bind the "correct" answer to
              // a different on-screen option than the one actually
              // shuffled into that slot, silently marking a genuinely
              // correct tap as wrong.
              final indexed = List.generate(
                q.options.length,
                (i) => MapEntry(i, q.options[i]),
              )..shuffle(_random);

              return Question(
                id: q.id,
                category: q.category,
                subcategory: q.subcategory,
                difficulty: q.difficulty,
                question: q.question,
                options: indexed.map((e) => e.value).toList(),
                correctIndex: indexed.indexWhere(
                  (e) => e.key == correctOriginalIndex,
                ),
              );
            })
            .whereType<Question>()
            .toList();

    result.shuffle(_random);
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

    final List<Question> filtered =
        _allQuestions.where((q) => q.category == selectedCategory).toList();

    return _sampleCloneAndFixOptions(filtered, count);
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

    final List<Question> picked = [];

    blueprint.forEach((category, needed) {
      final List<Question> pool =
          _allQuestions.where((q) => q.category == category).toList();

      // Only the handful this blueprint actually needs gets cloned, rather
      // than every question in the category. See _sampleCloneAndFixOptions.
      picked.addAll(_sampleCloneAndFixOptions(pool, needed));
    });

    // Already cloned above -- this second pass only needs to randomise the
    // order the categories appear in, so it shuffles in place instead of
    // cloning everything a second time.
    picked.shuffle(_random);

    if (picked.length <= count) return picked;
    return picked.take(count).toList();
  }

  /// Practice Mode: looks up the player's saved wrong-question IDs against
  /// the full bank. IDs that no longer exist (e.g. removed in a future
  /// content update) are silently skipped rather than crashing. Order
  /// follows [ids] as given (most-recent-mistake-last, matching
  /// PlayerService.wrongQuestionIds) unless [shuffleOrder] is true.
  static List<Question> getQuestionsForPracticeMode(
    List<String> ids, {
    bool shuffleOrder = true,
  }) {
    if (!_loaded || ids.isEmpty) return [];

    final Map<String, Question> byId = {for (final q in _allQuestions) q.id: q};

    final List<Question> found =
        ids
            .map((id) => byId[id])
            .whereType<Question>()
            .toList();

    final List<Question> fixed = _cloneShuffleAndFixOptions(found);

    if (!shuffleOrder) {
      // _cloneShuffleAndFixOptions always shuffles order too, so if the
      // caller wants original order preserved, re-sort back to it.
      final Map<String, Question> fixedById = {
        for (final q in fixed) q.id: q,
      };
      return ids
          .map((id) => fixedById[id])
          .whereType<Question>()
          .toList();
    }

    return fixed;
  }

  static List<Question> getQuestionsForRapidFire({int count = 20}) {
    if (!_loaded) return [];

    final List<Question> fastPool = [];

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

    // Sampled rather than cloning the whole pool -- this runs mid-round in
    // Rapid Fire, on the UI thread. See _sampleCloneAndFixOptions.
    return _sampleCloneAndFixOptions(fastPool, count);
  }
}
