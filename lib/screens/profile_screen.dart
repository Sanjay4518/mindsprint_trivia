import 'package:flutter/material.dart';
import '../services/player_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  void loadProfile() async {
    await PlayerService.loadPlayer();
    if (!mounted) return;
    setState(() {
      nameController.text = PlayerService.username;
    });
  }

  void saveName() async {
    await PlayerService.updateUsername(nameController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Profile updated")));
    setState(() {});
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Widget infoTile(String title, String value, Color accent) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildLeagueProgressCard() {
    final progress = PlayerService.getLeagueProgress();
    final nextLeague = PlayerService.getNextLeagueName();
    final xpToNext = PlayerService.getXpToNextLeague();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "League Progress",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFF2B3242),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.blueAccent,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            nextLeague == "Max League"
                ? "You are already in the highest league."
                : "$xpToNext XP needed to reach $nextLeague",
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final league = PlayerService.getLeague();

    return Scaffold(
      appBar: AppBar(title: const Text("Profile")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D2B64), Color(0xFF4F8CFF)],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                children: const [
                  CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, size: 36, color: Colors.white),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "Player Profile",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF181C24),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Player Name",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF232A36),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      hintText: "Enter your name",
                      hintStyle: const TextStyle(color: Colors.white38),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saveName,
                      child: const Text("Save"),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            buildLeagueProgressCard(),
            infoTile("Total XP", "${PlayerService.totalXp}", Colors.amber),
            infoTile(
              "Games Played",
              "${PlayerService.gamesPlayed}",
              Colors.greenAccent,
            ),
            infoTile("League", league, Colors.lightBlueAccent),
          ],
        ),
      ),
    );
  }
}
