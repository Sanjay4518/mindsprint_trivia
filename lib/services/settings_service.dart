import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static bool sfxOn = true;

  /// Opt-in, off by default. When true AND the player is linked with
  /// Google, their Google account photo is written into their public
  /// leaderboard entry (see LeaderboardRepository.syncCurrentEntry) so
  /// every other player who opens the leaderboard can see it -- otherwise
  /// they just see the generic league badge, same as before this setting
  /// existed. This is a bigger privacy commitment than a username (a
  /// linked Google photo isn't necessarily a photo the player expects to
  /// be shown to strangers), which is why it defaults to off and lives
  /// behind an explicit toggle rather than shipping on for every linked
  /// account.
  static bool showPhotoOnLeaderboard = false;

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    sfxOn = prefs.getBool("sfxOn") ?? true;
    showPhotoOnLeaderboard = prefs.getBool("showPhotoOnLeaderboard") ?? false;
  }

  static Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool("sfxOn", sfxOn);
    await prefs.setBool("showPhotoOnLeaderboard", showPhotoOnLeaderboard);
  }

  static Future<void> toggleSfx() async {
    sfxOn = !sfxOn;
    await saveSettings();
  }

  static Future<void> setShowPhotoOnLeaderboard(bool value) async {
    showPhotoOnLeaderboard = value;
    await saveSettings();
  }
}
