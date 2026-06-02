import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static bool musicOn = true;
  static bool sfxOn = true;

  static Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    musicOn = prefs.getBool("musicOn") ?? true;
    sfxOn = prefs.getBool("sfxOn") ?? true;
  }

  static Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool("musicOn", musicOn);
    await prefs.setBool("sfxOn", sfxOn);
  }

  static Future<void> toggleMusic() async {
    musicOn = !musicOn;
    await saveSettings();
  }

  static Future<void> toggleSfx() async {
    sfxOn = !sfxOn;
    await saveSettings();
  }
}
