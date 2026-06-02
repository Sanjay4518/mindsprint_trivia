import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../services/audio_service.dart';
import 'game_info_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    SettingsService.loadSettings().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void toggleMusic() async {
    await SettingsService.toggleMusic();
    await AudioService.refreshMusic();
    if (mounted) {
      setState(() {});
    }
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
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeColor: color,
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
          child: Text(subtitle, style: const TextStyle(color: Colors.white54)),
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
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54)),
        trailing: const Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: Colors.white54,
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
              title: "Background Music",
              subtitle: "Turn menu and gameplay music on or off",
              value: SettingsService.musicOn,
              onChanged: (_) => toggleMusic(),
              icon: Icons.music_note,
              color: Colors.blueAccent,
            ),
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
          ],
        ),
      ),
    );
  }
}
