import 'package:flutter/material.dart';

/// Shared "subtle color/texture" visual language for MindSprint Trivia.
///
/// This is the same look that was first shipped on the Player Dashboard's
/// Performance tiles and approved (via a preview mockup) to roll out app-wide:
/// a soft diagonal color-wash gradient fading into the app's dark card
/// background, with a slightly-more-visible tinted border. It reads as
/// "premium and sleek," not loud -- the accent color should always be doing
/// the work, never a hard block of color.
///
/// Keeping this in one place means every screen pulls from the same recipe
/// instead of re-deriving slightly different alpha values by hand.
class AppDecor {
  AppDecor._();

  /// The app's base dark card color, used as the far end of every gradient
  /// so cards still settle back into the normal dark theme.
  static const Color cardBase = Color(0xFF181C24);

  /// The app's base dark screen background.
  static const Color screenBase = Color(0xFF0B0E14);

  /// Standard tinted-gradient card decoration: [accent] washes in from the
  /// top-left and fades into the dark card base by the time it reaches the
  /// bottom-right. Use this for any card, tile, or panel that should carry a
  /// bit of that accent's color without looking like a solid colored block.
  static BoxDecoration cardDecoration(
    Color accent, {
    double radius = 18,
    double topAlpha = 0.20,
    double borderAlpha = 0.40,
    double stop = 0.65,
  }) {
    return BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent.withValues(alpha: topAlpha), cardBase],
        stops: [0.0, stop],
      ),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: borderAlpha)),
    );
  }

  /// A slightly stronger version of [cardDecoration] for hero/primary cards
  /// (e.g. a mode's main entry card) where the texture can afford to read a
  /// touch bolder without tipping into "too busy."
  static BoxDecoration heroCardDecoration(
    Color accent, {
    double radius = 22,
  }) {
    return cardDecoration(
      accent,
      radius: radius,
      topAlpha: 0.26,
      borderAlpha: 0.5,
      stop: 0.75,
    );
  }

  /// Subtle whole-screen background texture: a very soft radial glow of
  /// [accent] (or a neutral cool tone if none is given) low in the corner,
  /// settling into the app's normal near-black background. Meant to replace
  /// flat solid-black screen backgrounds with something that has a little
  /// life to it, without competing with foreground content or costing any
  /// image assets.
  static BoxDecoration screenBackgroundDecoration({Color? accent}) {
    final Color tint = accent ?? const Color(0xFF3B82F6);
    return BoxDecoration(
      gradient: RadialGradient(
        center: const Alignment(-0.9, -1.0),
        radius: 1.6,
        colors: [tint.withValues(alpha: 0.16), screenBase],
        stops: const [0.0, 0.6],
      ),
    );
  }
}
