import 'dart:async';
import 'package:flutter/material.dart';
import 'services/ad_service.dart';
import 'services/audio_service.dart';
import 'services/player_service.dart';
import 'services/question_service.dart';
import 'services/settings_service.dart';
import 'services/stamina_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await PlayerService.loadPlayer();
  await StaminaService.loadStamina();
  await SettingsService.loadSettings();
  await QuestionService.loadQuestions();
  unawaited(AdService.instance.initialize());

  // TEMP ONLY:
  // Keep this for one run if premium is stuck from earlier testing.
  // After confirming premium is reset, REMOVE this line.

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    AudioService.startMusic();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MindSprint Trivia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1117),
        primaryColor: const Color(0xFF4F8CFF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4F8CFF),
          secondary: Color(0xFFFF8A3D),
          surface: Color(0xFF181C24),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F1117),
          elevation: 0,
          centerTitle: true,
          foregroundColor: Colors.white,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
