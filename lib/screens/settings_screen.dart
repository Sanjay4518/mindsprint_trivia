import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import 'game_info_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Kept as a plain literal (no package_info_plus dependency) so this is a
  // zero-risk, zero-new-dependency addition -- must be bumped by hand
  // whenever pubspec.yaml's `version:` line changes. Matches pubspec.yaml's
  // versionName+versionCode convention so it's directly comparable to what
  // Play Console shows.
  static const String _appVersion = "1.0.0+12";

  @override
  void initState() {
    super.initState();
    SettingsService.loadSettings().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void toggleSfx() async {
    await SettingsService.toggleSfx();
    if (mounted) {
      setState(() {});
    }
  }

  Widget buildToggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
      ),
      // Wrapped in a transparent Material -- SwitchListTile/ListTile need a
      // Material ancestor of their own to paint correctly; without one
      // Flutter logs a harmless but noisy "ListTile background color or
      // ink splashes may be invisible" exception (this is what shows as a
      // brief red error banner on-screen even though nothing is broken).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          value: value,
          onChanged: onChanged,
          activeThumbColor: color,
          title: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Text(
              subtitle,
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: color),
          title: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54),
          ),
          trailing: const Icon(
            Icons.arrow_forward_ios_rounded,
            size: 16,
            color: Colors.white54,
          ),
        ),
      ),
    );
  }

  void openGameInfo() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const GameInfoScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            buildToggleTile(
              title: "Sound Effects",
              subtitle: "Control answer sounds and gameplay feedback",
              value: SettingsService.sfxOn,
              onChanged: (_) => toggleSfx(),
              icon: Icons.graphic_eq,
              color: Colors.orangeAccent,
            ),
            buildActionTile(
              title: "Game Info",
              subtitle: "Rules, scoring, stamina, premium and mode details",
              icon: Icons.info_outline_rounded,
              color: Colors.lightBlueAccent,
              onTap: openGameInfo,
            ),
            const SizedBox(height: 24),
            const Text(
              "MindSprint Trivia v$_appVersion",
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
