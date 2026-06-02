import 'package:shared_preferences/shared_preferences.dart';
import 'league_service.dart';

class PlayerService {
  static String username = "Player";
  static int totalXp = 0;
  static int gamesPlayed = 0;
  static bool isPremium = false;

  static Future<void> loadPlayer() async {
    final prefs = await SharedPreferences.getInstance();

    username = prefs.getString("username") ?? "Player";
    totalXp = prefs.getInt("xp") ?? 0;
    gamesPlayed = prefs.getInt("games") ?? 0;
    isPremium = prefs.getBool("premium") ?? false;
  }

  static Future<void> savePlayer() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString("username", username);
    await prefs.setInt("xp", totalXp);
    await prefs.setInt("games", gamesPlayed);
    await prefs.setBool("premium", isPremium);
  }

  static Future<void> updateUsername(String name) async {
    username = name.trim().isEmpty ? "Player" : name.trim();
    await savePlayer();
  }

  static Future<void> addXp(int xp) async {
    totalXp += xp;
    gamesPlayed++;
    await savePlayer();
  }

  static Future<void> setPremium(bool value) async {
    isPremium = value;
    await savePlayer();
  }

  static String getLeague() {
    return LeagueService.leagueForXp(totalXp).name;
  }

  static int getCurrentLeagueMinXp() {
    return LeagueService.leagueForXp(totalXp).minXp;
  }

  static int? getNextLeagueMinXp() {
    return LeagueService.nextLeagueForXp(totalXp)?.minXp;
  }

  static String getNextLeagueName() {
    return LeagueService.nextLeagueForXp(totalXp)?.name ?? "Max League";
  }

  static double getLeagueProgress() {
    return LeagueService.progressForXp(totalXp).progress;
  }

  static int getXpToNextLeague() {
    return LeagueService.progressForXp(totalXp).xpToNextLeague;
  }

  static String getPerformanceBadge(double accuracy) {
    if (accuracy >= 90) return "Elite Performer";
    if (accuracy >= 75) return "Sharp Mind";
    if (accuracy >= 50) return "Getting There";
    return "Needs Improvement";
  }

  static String getPerformanceMessage(double accuracy) {
    if (accuracy >= 90) return "Outstanding performance!";
    if (accuracy >= 75) return "Great job, keep pushing!";
    if (accuracy >= 50) return "Decent effort, improve accuracy.";
    return "Focus and try again.";
  }

  static List<Map<String, dynamic>> getLeaderboardForLeague(String league) {
    final Map<String, List<Map<String, dynamic>>> leaguePlayers = {
      "Bronze": [
        {"name": username, "xp": totalXp, "league": getLeague()},
        {"name": "Player B1", "xp": 420, "league": "Bronze"},
        {"name": "Player B2", "xp": 380, "league": "Bronze"},
        {"name": "Player B3", "xp": 335, "league": "Bronze"},
        {"name": "Player B4", "xp": 290, "league": "Bronze"},
        {"name": "Player B5", "xp": 240, "league": "Bronze"},
        {"name": "Player B6", "xp": 180, "league": "Bronze"},
        {"name": "Player B7", "xp": 130, "league": "Bronze"},
      ],
      "Silver": [
        {"name": "Player S1", "xp": 1450, "league": "Silver"},
        {"name": "Player S2", "xp": 1320, "league": "Silver"},
        {"name": "Player S3", "xp": 1190, "league": "Silver"},
        {"name": "Player S4", "xp": 1050, "league": "Silver"},
        {"name": "Player S5", "xp": 970, "league": "Silver"},
        {"name": "Player S6", "xp": 880, "league": "Silver"},
      ],
      "Gold": [
        {"name": "Player G1", "xp": 2840, "league": "Gold"},
        {"name": "Player G2", "xp": 2490, "league": "Gold"},
        {"name": "Player G3", "xp": 2250, "league": "Gold"},
        {"name": "Player G4", "xp": 1990, "league": "Gold"},
        {"name": "Player G5", "xp": 1720, "league": "Gold"},
      ],
      "Platinum": [
        {"name": "Player P1", "xp": 4700, "league": "Platinum"},
        {"name": "Player P2", "xp": 4380, "league": "Platinum"},
        {"name": "Player P3", "xp": 4010, "league": "Platinum"},
        {"name": "Player P4", "xp": 3520, "league": "Platinum"},
        {"name": "Player P5", "xp": 3200, "league": "Platinum"},
      ],
      "Diamond": [
        {"name": "Player D1", "xp": 8200, "league": "Diamond"},
        {"name": "Player D2", "xp": 7600, "league": "Diamond"},
        {"name": "Player D3", "xp": 7050, "league": "Diamond"},
        {"name": "Player D4", "xp": 6400, "league": "Diamond"},
      ],
      "Master": [
        {"name": "Player M1", "xp": 11600, "league": "Master"},
        {"name": "Player M2", "xp": 10500, "league": "Master"},
        {"name": "Player M3", "xp": 9400, "league": "Master"},
      ],
      "Legend": [
        {"name": "Player L1", "xp": 18400, "league": "Legend"},
        {"name": "Player L2", "xp": 15100, "league": "Legend"},
        {"name": "Player L3", "xp": 12800, "league": "Legend"},
      ],
    };

    final players = List<Map<String, dynamic>>.from(
      leaguePlayers[league] ?? [],
    );

    if (getLeague() == league) {
      final alreadyExists = players.any((p) => p["name"] == username);
      if (!alreadyExists) {
        players.add({"name": username, "xp": totalXp, "league": getLeague()});
      }
    }

    players.sort((a, b) => (b["xp"] as int).compareTo(a["xp"] as int));

    for (int i = 0; i < players.length; i++) {
      players[i]["rank"] = i + 1;
    }

    return players;
  }
}
