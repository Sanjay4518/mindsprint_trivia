import 'package:flutter/material.dart';
import '../services/league_service.dart';
import '../services/player_service.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late String selectedLeague;

  final List<String> leagues = LeagueService.leagueNames;

  @override
  void initState() {
    super.initState();
    selectedLeague = PlayerService.getLeague();
  }

  Color getLeagueColor(String league) {
    return LeagueService.colorForLeague(league);
  }

  @override
  Widget build(BuildContext context) {
    final players = PlayerService.getLeaderboardForLeague(selectedLeague);

    return Scaffold(
      appBar: AppBar(title: const Text("Leaderboard")),
      body: Column(
        children: [
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              itemCount: leagues.length,
              itemBuilder: (context, index) {
                final league = leagues[index];
                final selected = league == selectedLeague;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedLeague = league;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? getLeagueColor(league).withValues(alpha: 0.18)
                              : const Color(0xFF181C24),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color:
                            selected ? getLeagueColor(league) : Colors.white10,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      league,
                      style: TextStyle(
                        color:
                            selected ? getLeagueColor(league) : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF181C24),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              "Showing $selectedLeague League",
              style: TextStyle(
                color: getLeagueColor(selectedLeague),
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: players.length,
              itemBuilder: (context, index) {
                final player = players[index];
                final isYou = player["name"] == PlayerService.username;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color:
                        isYou
                            ? const Color(0xFF1B2333)
                            : const Color(0xFF181C24),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color:
                          isYou
                              ? getLeagueColor(selectedLeague)
                              : Colors.white10,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            "#${player["rank"]}",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              player["name"],
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color:
                                    isYou
                                        ? getLeagueColor(selectedLeague)
                                        : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              player["league"],
                              style: TextStyle(
                                color: getLeagueColor(player["league"]),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        "${player["xp"]} XP",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
