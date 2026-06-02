import 'package:audioplayers/audioplayers.dart';
import 'settings_service.dart';

class AudioService {
  static final AudioPlayer _bgPlayer = AudioPlayer();
  static bool _isPlaying = false;

  static Future<void> playSfx(String fileName) async {
    if (!SettingsService.sfxOn) return;

    final player = AudioPlayer();
    await player.play(AssetSource('sounds/$fileName'));
  }

  static Future<void> startMusic() async {
    if (!SettingsService.musicOn) return;
    if (_isPlaying) return;

    await _bgPlayer.setReleaseMode(ReleaseMode.loop);
    await _bgPlayer.setVolume(0.2);
    await _bgPlayer.play(AssetSource('sounds/bg_music.wav'));

    _isPlaying = true;
  }

  static Future<void> stopMusic() async {
    await _bgPlayer.stop();
    _isPlaying = false;
  }

  static Future<void> refreshMusic() async {
    if (SettingsService.musicOn) {
      await startMusic();
    } else {
      await stopMusic();
    }
  }
}
