import 'package:flutter/material.dart';
import '../models/league.dart';

class LeagueProgress {
  final League currentLeague;
  final League? nextLeague;
  final double progress;
  final int xpToNextLeague;
  final bool isMaxLeague;

  const LeagueProgress({
    required this.currentLeague,
    required this.nextLeague,
    required this.progress,
    required this.xpToNextLeague,
  }) : isMaxLeague = nextLeague == null;
}

class LeagueService {
  static const List<League> leagues = [
    League(
      name: "Bronze",
      minXp: 0,
      maxXp: 500,
      color: Color(0xFFB87333),
      icon: Icons.military_tech_rounded,
    ),
    League(
      name: "Silver",
      minXp: 500,
      maxXp: 1500,
      color: Color(0xFFC0C0C0),
      icon: Icons.workspace_premium_rounded,
    ),
    League(
      name: "Gold",
      minXp: 1500,
      maxXp: 3000,
      color: Color(0xFFFFC107),
      icon: Icons.emoji_events_rounded,
    ),
    League(
      name: "Platinum",
      minXp: 3000,
      maxXp: 5000,
      color: Color(0xFF80DEEA),
      icon: Icons.diamond_rounded,
    ),
    League(
      name: "Diamond",
      minXp: 5000,
      maxXp: 8000,
      color: Color(0xFF40E0D0),
      icon: Icons.diamond_outlined,
    ),
    League(
      name: "Master",
      minXp: 8000,
      maxXp: 12000,
      color: Color(0xFFB388FF),
      icon: Icons.auto_awesome_rounded,
    ),
    League(
      name: "Legend",
      minXp: 12000,
      maxXp: null,
      color: Color(0xFFFF7043),
      icon: Icons.local_fire_department_rounded,
    ),
  ];

  static League leagueForXp(int xp) {
    return leagues.lastWhere(
      (league) => league.containsXp(xp),
      orElse: () => leagues.first,
    );
  }

  static League? nextLeagueForXp(int xp) {
    final currentIndex = leagues.indexOf(leagueForXp(xp));
    if (currentIndex < 0 || currentIndex == leagues.length - 1) return null;
    return leagues[currentIndex + 1];
  }

  static LeagueProgress progressForXp(int xp) {
    final current = leagueForXp(xp);
    final next = nextLeagueForXp(xp);

    if (next == null) {
      return LeagueProgress(
        currentLeague: current,
        nextLeague: null,
        progress: 1.0,
        xpToNextLeague: 0,
      );
    }

    final span = next.minXp - current.minXp;
    final earnedInLeague = xp - current.minXp;

    return LeagueProgress(
      currentLeague: current,
      nextLeague: next,
      progress:
          span <= 0 ? 1.0 : (earnedInLeague / span).clamp(0.0, 1.0).toDouble(),
      xpToNextLeague: (next.minXp - xp).clamp(0, next.minXp).toInt(),
    );
  }

  static List<String> get leagueNames =>
      leagues.map((league) => league.name).toList(growable: false);

  static int rankForLeague(String leagueName) {
    final index = leagues.indexWhere((league) => league.name == leagueName);
    return index < 0 ? 0 : index;
  }

  static Color colorForLeague(String leagueName) {
    return leagues
        .firstWhere(
          (league) => league.name == leagueName,
          orElse: () => leagues.first,
        )
        .color;
  }
}
