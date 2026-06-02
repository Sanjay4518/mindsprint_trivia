import 'package:shared_preferences/shared_preferences.dart';
import 'player_service.dart';

class StaminaService {
  static const int maxStamina = 60;

  static int currentStamina = 60;
  static int lastUsedStamina = 0;

  static DateTime? lastUpdateTime;

  static int get visibleStamina {
    if (PlayerService.isPremium) return maxStamina;
    return currentStamina;
  }

  static Future<void> loadStamina() async {
    final prefs = await SharedPreferences.getInstance();

    currentStamina = prefs.getInt("stamina") ?? maxStamina;

    String? lastTime = prefs.getString("lastUpdate");

    if (lastTime != null) {
      lastUpdateTime = DateTime.parse(lastTime);
      refillStamina();
    } else {
      lastUpdateTime = DateTime.now();
      await saveStamina();
    }

    if (PlayerService.isPremium) {
      currentStamina = maxStamina;
      lastUsedStamina = 0;
      await saveStamina();
    }
  }

  static Future<void> saveStamina() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt("stamina", currentStamina);
    await prefs.setString(
      "lastUpdate",
      (lastUpdateTime ?? DateTime.now()).toIso8601String(),
    );
  }

  static void refillStamina() {
    if (PlayerService.isPremium) return;
    if (lastUpdateTime == null) return;

    DateTime now = DateTime.now();

    int minutesPassed = now.difference(lastUpdateTime!).inMinutes;
    int staminaToAdd = minutesPassed ~/ 4;

    if (staminaToAdd > 0) {
      currentStamina += staminaToAdd;

      if (currentStamina > maxStamina) {
        currentStamina = maxStamina;
      }

      lastUpdateTime = now;
      saveStamina();
    }
  }

  static Future<void> refreshStamina() async {
    await loadStamina();
  }

  static Future<void> addStamina(int amount) async {
    if (PlayerService.isPremium) return;

    currentStamina += amount;

    if (currentStamina > maxStamina) {
      currentStamina = maxStamina;
    }

    lastUpdateTime = DateTime.now();
    await saveStamina();
  }

  static bool canPlay(int cost) {
    if (PlayerService.isPremium) return true;
    return currentStamina >= cost;
  }

  static Future<void> unlockPremiumStamina() async {
    currentStamina = maxStamina;
    lastUsedStamina = 0;
    lastUpdateTime = DateTime.now();
    await saveStamina();
  }

  static Future<bool> useStamina(int cost) async {
    if (PlayerService.isPremium) {
      lastUsedStamina = 0;
      return true;
    }

    if (currentStamina < cost) return false;

    currentStamina -= cost;
    lastUsedStamina = cost;

    if (currentStamina < 0) {
      currentStamina = 0;
    }

    lastUpdateTime = DateTime.now();
    await saveStamina();
    return true;
  }
}
