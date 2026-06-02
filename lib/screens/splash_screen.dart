import 'dart:async';
import 'package:flutter/material.dart';
import '../services/ad_service.dart';
import '../services/audio_service.dart';
import '../services/player_service.dart';
import '../services/question_service.dart';
import '../services/settings_service.dart';
import '../services/stamina_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    initializeApp();
  }

  Future<void> initializeApp() async {
    await PlayerService.loadPlayer();
    await StaminaService.loadStamina();
    await SettingsService.loadSettings();
    await QuestionService.loadQuestions();
    await AudioService.startMusic();
    unawaited(AdService.instance.initialize());

    if (!mounted) return;

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: const Color(0xFF181C24),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFF4F8CFF)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF4F8CFF).withValues(alpha: 0.22),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.psychology_alt_rounded,
                    color: Color(0xFF4F8CFF),
                    size: 52,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  "MindSprint Trivia",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Train faster. Recall sharper.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 28),
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.8,
                    color: Color(0xFF4F8CFF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
