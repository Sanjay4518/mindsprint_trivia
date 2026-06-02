import 'package:shared_preferences/shared_preferences.dart';
import 'player_service.dart';

class UsageLimitService {
  static const int freeRapidFireRoundsPerDay = 2;
  static const int freeNormalQuestionsPerDay = 40;

  static String _todayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month}-${now.day}";
  }

  static Future<void> _resetIfNeeded(SharedPreferences prefs) async {
    final today = _todayKey();
    final savedDate = prefs.getString("usageDate");

    if (savedDate == today) return;

    await prefs.setString("usageDate", today);
    await prefs.setInt("rapidFireRoundsToday", 0);
    await prefs.setInt("normalQuestionsToday", 0);
  }

  static Future<int> getRapidFireRoundsToday() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    return prefs.getInt("rapidFireRoundsToday") ?? 0;
  }

  static Future<bool> canStartRapidFire() async {
    if (PlayerService.isPremium) return true;
    return await getRapidFireRoundsToday() < freeRapidFireRoundsPerDay;
  }

  static Future<void> recordRapidFireRoundStarted() async {
    if (PlayerService.isPremium) return;

    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    final rounds = prefs.getInt("rapidFireRoundsToday") ?? 0;
    await prefs.setInt("rapidFireRoundsToday", rounds + 1);
  }

  static Future<int> getNormalQuestionsToday() async {
    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);
    return prefs.getInt("normalQuestionsToday") ?? 0;
  }

  static Future<bool> canStartNormalQuestionSet(int questionCount) async {
    if (PlayerService.isPremium) return true;
    final used = await getNormalQuestionsToday();
    return used + questionCount <= freeNormalQuestionsPerDay;
  }

  static Future<void> recordNormalQuestionsStarted(int questionCount) async {
    if (PlayerService.isPremium) return;

    final prefs = await SharedPreferences.getInstance();
    await _resetIfNeeded(prefs);

    final used = prefs.getInt("normalQuestionsToday") ?? 0;
    await prefs.setInt("normalQuestionsToday", used + questionCount);
  }
}
