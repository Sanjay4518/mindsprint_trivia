import 'package:audioplayers/audioplayers.dart';
import 'settings_service.dart';

class AudioService {
  // A single shared player, reused for every SFX call. The previous
  // version constructed a brand-new AudioPlayer() on every single tap and
  // never disposed it -- each one registers a real native
  // MediaPlayer/SoundPool on the platform side, so a long Rapid Fire
  // session (30-50+ taps, no per-question timer to slow the player down)
  // could leak 100+ native players in one sitting. Symptoms show up as
  // native memory climbing, then SFX getting flaky, then SFX silently
  // stopping altogether -- very hard to diagnose from a bug report.
  //
  // Reusing one player means back-to-back sounds cut each other off
  // (stop() before every play()) rather than overlapping. That's an
  // acceptable trade for short UI blips like these; if overlapping SFX is
  // ever wanted, replace this with a small fixed-size pool instead of
  // unbounded allocation.
  static final AudioPlayer _player = AudioPlayer()
    ..setReleaseMode(ReleaseMode.stop);

  static Future<void> playSfx(String fileName) async {
    if (!SettingsService.sfxOn) return;

    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$fileName'));
    } catch (_) {
      // A missing asset, denied audio focus, or a platform hiccup should
      // never be worth interrupting gameplay for -- SFX is cosmetic.
    }
  }
}
