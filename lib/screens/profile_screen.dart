import 'package:flutter/material.dart';
import '../services/league_service.dart';
import '../services/player_service.dart';
import '../widgets/league_badge.dart';

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

  Future<void> loadProfile() async {
    await PlayerService.loadPlayer();
    if (!mounted) return;
    setState(() {
      nameController.text = PlayerService.username;
    });
  }

  Future<void> saveName() async {
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

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget statTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHeader() {
    final progress = LeagueService.progressForXp(PlayerService.totalXp);
    final league = progress.currentLeague;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: league.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          LeagueBadge(league: league, size: 68),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PlayerService.username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${league.name} League",
                  style: TextStyle(
                    color: league.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "${PlayerService.totalXp} total XP",
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildNameEditor() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Username",
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF232A36),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: saveName,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8CFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text("Save"),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = LeagueService.progressForXp(PlayerService.totalXp);

    return Scaffold(
      appBar: AppBar(title: const Text("Player Dashboard")),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              buildHeader(),
              const SizedBox(height: 16),
              LeagueProgressCard(
                currentLeague: progress.currentLeague,
                nextLeague: progress.nextLeague,
                progress: progress.progress,
                xpToNextLeague: progress.xpToNextLeague,
                totalXp: PlayerService.totalXp,
              ),
              const SizedBox(height: 20),
              sectionTitle("Performance"),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.35,
                children: [
                  statTile(
                    title: "Games Played",
                    value: "${PlayerService.gamesPlayed}",
                    icon: Icons.sports_esports_rounded,
                    color: Colors.greenAccent,
                  ),
                  statTile(
                    title: "Accuracy",
                    value:
                        "${PlayerService.accuracyPercentage.toStringAsFixed(1)}%",
                    icon: Icons.track_changes_rounded,
                    color: Colors.orangeAccent,
                  ),
                  statTile(
                    title: "Questions",
                    value: "${PlayerService.totalQuestionsAnswered}",
                    icon: Icons.quiz_rounded,
                    color: Colors.lightBlueAccent,
                  ),
                  statTile(
                    title: "Rapid High Score",
                    value: "${PlayerService.rapidFireHighScore}",
                    icon: Icons.flash_on_rounded,
                    color: Colors.pinkAccent,
                  ),
                  statTile(
                    title: "Correct",
                    value: "${PlayerService.correctAnswers}",
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  statTile(
                    title: "Wrong",
                    value: "${PlayerService.wrongAnswers}",
                    icon: Icons.cancel_rounded,
                    color: Colors.redAccent,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              sectionTitle("Profile"),
              buildNameEditor(),
            ],
          ),
        ),
      ),
    );
  }
}
