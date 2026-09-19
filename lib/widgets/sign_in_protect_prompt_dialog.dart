import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/player_service.dart';

/// A dismissible "protect your progress" sign-in nudge, separate from
/// HomeScreen's one-time first-launch prompt (see
/// HomeScreen._maybeShowFirstLaunchSignInPrompt, which fires once right at
/// app start for a very different reason -- checking for pre-existing
/// history). This one is about a guest who's already built up real local
/// progress on THIS install and would lose it if the app were ever
/// uninstalled or the device lost/replaced -- so it's timed around two
/// specific moments that make that risk concrete rather than abstract:
///
/// 1. Right after the player's FIRST league promotion -- the exact moment
///    they've just been shown proof they have something worth protecting
///    (see [maybeShow]'s `justPromoted` parameter, driven by
///    PromotionCelebrationDialog.showIfPending's return value).
/// 2. If that's dismissed (or never triggers because they haven't been
///    promoted yet), a single backoff re-prompt once they've played 15
///    rounds -- enough real progress banked that "you could lose this" is
///    true, without nagging a brand-new guest on round 2.
///
/// Each of the two moments shows at most once ever (see the two
/// SharedPreferences flags below) -- this never asks more than twice
/// across an install's whole lifetime, and never asks again at all once
/// linked. Both checks are silently skipped once [AuthService.isLinkedWithGoogle].
class SignInProtectPromptDialog {
  static const _shownAfterPromotionKey = 'signInPromptShownAfterPromotion';
  static const _shownAtGame15Key = 'signInPromptShownAtGame15';

  /// Game-count threshold for the backoff re-prompt -- see the class doc
  /// comment. Kept as a named constant rather than a bare 15 so the "why
  /// 15" reasoning above stays attached to one place if this ever needs
  /// tuning.
  static const int _game15Threshold = 15;

  /// Call this right after [PromotionCelebrationDialog.showIfPending]
  /// resolves, from every screen that calls it (ResultScreen,
  /// RapidFireResultScreen) -- passing its return value straight through as
  /// [justPromoted]. Does nothing at all for a player who's already linked
  /// a Google account, or when neither trigger applies right now.
  ///
  /// Returns true only when the player actually tapped "Sign In" -- the
  /// caller (not this widget) owns navigating to ProfileScreen with that
  /// result, same division of responsibility as every other dialog in the
  /// app that can lead somewhere else (see HomeScreen's own sign-in and
  /// practice-locked prompts).
  static Future<bool> maybeShow(
    BuildContext context, {
    required bool justPromoted,
  }) async {
    if (AuthService.isLinkedWithGoogle) return false;
    if (!context.mounted) return false;

    final prefs = await SharedPreferences.getInstance();
    final shownAfterPromotion = prefs.getBool(_shownAfterPromotionKey) ?? false;
    final shownAtGame15 = prefs.getBool(_shownAtGame15Key) ?? false;

    final bool showAsPromotion = justPromoted && !shownAfterPromotion;
    final bool showAsGame15 =
        !showAsPromotion &&
        !shownAtGame15 &&
        PlayerService.gamesPlayed >= _game15Threshold;

    if (!showAsPromotion && !showAsGame15) return false;
    if (!context.mounted) return false;

    // Same reasoning as PromotionCelebrationDialog.showIfPending: a fast
    // Play Again tap can leave this screen "mounted" even though a new
    // round is already on top of it. Never pop a dialog over live
    // gameplay -- if this loses the race, it simply doesn't get asked this
    // moment; the game-15 backoff (for a missed promotion prompt) or next
    // promotion (for a missed game-15 prompt) still gets another chance.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;

    // Recorded before showing, not after -- matches
    // PromotionCelebrationDialog's own reasoning: nothing below can throw
    // in a way that would leave this stuck un-recorded, and recording
    // first means this can never double-show even from a stray re-entrant
    // call.
    if (showAsPromotion) {
      await prefs.setBool(_shownAfterPromotionKey, true);
    } else {
      await prefs.setBool(_shownAtGame15Key, true);
    }

    if (!context.mounted) return false;

    // Re-check again, same reasoning as the isCurrent check above: the
    // prefs.setBool await just above is a real platform-channel round trip,
    // long enough for a rapid "Play Again" tap to land a new round on top of
    // this still-mounted screen in the meantime. Without this second check,
    // the dialog below would show over live gameplay instead of over the
    // (now-covered) result screen it was meant for.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;

    final String title = showAsPromotion ? "Protect this progress!" : "Don't lose your progress";
    final String body =
        showAsPromotion
            ? "Congrats on the promotion! Right now this is only saved on "
                "this device -- sign in with Google (free, takes a second) "
                "so a lost phone or a reinstall can never wipe it out."
            : "You've played ${PlayerService.gamesPlayed} rounds as a guest -- "
                "all of it is only saved on this device. Sign in with "
                "Google (free, takes a second) to back it up for good.";

    final bool? goToSignIn = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF121821),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            content: Text(
              body,
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text("Not now"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text("Sign In"),
              ),
            ],
          ),
    );

    return goToSignIn == true;
  }
}
