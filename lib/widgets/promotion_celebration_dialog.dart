import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/league_service.dart';
import '../services/player_service.dart';
import 'league_badge.dart';

/// A one-off celebratory dialog shown right after a round ends, when
/// [PlayerService] detects the player's league rank went up (see
/// PlayerService._detectPromotion / hasRecentPromotion). Purely a
/// celebration moment -- it doesn't gate or change anything about
/// gameplay, XP, or stamina. Uses only plain Flutter animation primitives
/// (a single AnimationController + Curves, the same pattern already used
/// for NormalModeScreen's timer pulse) -- no new packages, so nothing
/// needs `flutter pub get` to ship.
class PromotionCelebrationDialog extends StatefulWidget {
  final String fromLeagueName;
  final String toLeagueName;

  const PromotionCelebrationDialog({
    super.key,
    required this.fromLeagueName,
    required this.toLeagueName,
  });

  /// Shows this dialog if [PlayerService.hasRecentPromotion] is true right
  /// now, then immediately clears the pending promotion -- so even if the
  /// player backgrounds the app mid-animation and comes back, or this gets
  /// called again from another screen, the same promotion can never
  /// celebrate twice. Safe to call from any screen right after a round has
  /// been recorded (see ResultScreen/RapidFireResultScreen); does nothing
  /// at all if there's no promotion pending.
  ///
  /// Returns true only when the celebration actually displayed -- callers
  /// use this to chain SignInProtectPromptDialog's post-promotion trigger
  /// (see its `justPromoted` parameter) right after, without that widget
  /// needing to duplicate any of the race-guard checks below.
  static Future<bool> showIfPending(BuildContext context) async {
    if (!PlayerService.hasRecentPromotion) return false;
    if (!context.mounted) return false;

    // Only show over the screen that's actually on top right now. Play
    // Again (see ResultScreen/RapidFireResultScreen) pushes the next round
    // without removing the result screen underneath it, and the round-save
    // this runs after is a long chain of awaited SharedPreferences writes
    // -- so a fast tap on Play Again can leave `context` still "mounted"
    // even though a live game is now on top of it. Showing here in that
    // case would pop a non-dismissible dialog over active gameplay instead
    // of over the result screen where the promotion actually happened.
    // Leaving the promotion pending (not clearing it below) means it just
    // shows correctly the next time a result screen calls this and is
    // still the current route -- see PlayerService._detectPromotion, which
    // no longer wipes an unshown pending promotion out from under a later,
    // unrelated round.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;

    final fromLeague = PlayerService.lastPromotionFromLeague!;
    final toLeague = PlayerService.lastPromotionToLeague!;

    // Cleared before showing, not after -- the dialog itself can't fail or
    // throw in a way that would leave this stuck pending, and clearing
    // first means a stray double-call (e.g. something re-checking while
    // this is already in flight) can't ever show it twice.
    await PlayerService.clearRecentPromotion();

    if (!context.mounted) return false;
    // Re-checked after the await above for the same reason as the first
    // check -- a narrow window, but Play Again is a fast, deliberate tap
    // and clearRecentPromotion is a real (if quick) async write. If this
    // second check fails, the promotion is already cleared and simply
    // won't be celebrated for this round -- a much smaller, accepted
    // trade-off versus showing a blocking dialog over live gameplay.
    if (!(ModalRoute.of(context)?.isCurrent ?? false)) return false;

    AudioService.playSfx('correct.wav');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder:
          (_) => PromotionCelebrationDialog(
            fromLeagueName: fromLeague,
            toLeagueName: toLeague,
          ),
    );

    return true;
  }

  @override
  State<PromotionCelebrationDialog> createState() =>
      _PromotionCelebrationDialogState();
}

/// One decorative sparkle's animation spec: [angle] (radians, direction it
/// flies out from the badge), [distance] it travels, [size], and its own
/// [start]/[end] slice of the shared timeline so several sparkles stagger
/// in rather than all moving in lockstep.
class _SparkleSpec {
  final double angle;
  final double distance;
  final double start;
  final double end;
  final double size;

  const _SparkleSpec({
    required this.angle,
    required this.distance,
    required this.start,
    required this.end,
    required this.size,
  });
}

class _PromotionCelebrationDialogState
    extends State<PromotionCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Six sparkles spread evenly around the badge (60 degrees apart), each
  // starting its own outward fade at a slightly different moment so they
  // read as a little celebratory burst rather than one flat pop.
  static final List<_SparkleSpec> _sparkles = List.generate(6, (i) {
    final angle = (i / 6) * 2 * math.pi;
    return _SparkleSpec(
      angle: angle,
      distance: 58.0 + (i.isEven ? 4.0 : 0.0),
      start: 0.10 + (i * 0.02),
      end: 0.85 + (i * 0.02),
      size: i.isEven ? 16.0 : 13.0,
    );
  });

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// A 0-1 progress value scoped to [start, end] of the overall animation,
  /// clamped flat outside that window -- lets several pieces of the
  /// celebration stagger in from one shared controller instead of each
  /// needing its own.
  double _slice(double start, double end) {
    final t = _controller.value;
    if (t <= start) return 0.0;
    if (t >= end) return 1.0;
    return (t - start) / (end - start);
  }

  Widget _sparkle(_SparkleSpec s, Color color) {
    final travel = Curves.easeOut.transform(_slice(s.start, s.end));
    final fade =
        Curves.easeIn.transform(_slice(s.start, (s.start + s.end) / 2));
    final dx = s.distance * travel * math.cos(s.angle);
    final dy = s.distance * travel * math.sin(s.angle);

    // No Positioned wrapper -- this sparkle is a plain (non-positioned)
    // Stack child, so the parent Stack's `alignment: Alignment.center`
    // places it at the badge's center first, same as the badge itself;
    // the translate then carries it outward from there. An earlier
    // version wrapped this in `Positioned(left: 0, top: 0, ...)`, which
    // anchors at the Stack's top-left corner instead and ignores
    // `alignment` entirely -- every sparkle flew outward from one corner
    // of the 140x140 box rather than bursting symmetrically around the
    // centered badge.
    return Transform.translate(
      offset: Offset(dx, dy),
      child: Opacity(
        opacity: (1 - travel) * fade,
        child: Icon(Icons.auto_awesome_rounded, size: s.size, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromLeague = LeagueService.leagueForName(widget.fromLeagueName);
    final toLeague = LeagueService.leagueForName(widget.toLeagueName);

    return PopScope(
      // barrierDismissible: false (in showIfPending) only blocks tapping
      // the scrim -- it does nothing about the Android/system back
      // button, which would otherwise still pop this dialog by default.
      // The rest of the app is deliberately careful about this exact gap
      // (see the PopScope usage in result_screen.dart, normal_mode_screen
      // .dart, etc.) -- this dialog was missing the same guard.
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final badgeScale = Curves.elasticOut.transform(_slice(0.0, 0.75));
          final badgeOpacity = Curves.easeIn.transform(_slice(0.0, 0.25));
          final titleT = Curves.easeOut.transform(_slice(0.25, 0.55));
          final leaguesT = Curves.easeOut.transform(_slice(0.4, 0.7));
          final buttonT = Curves.easeOut.transform(_slice(0.65, 0.95));

          return Container(
            padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
            decoration: BoxDecoration(
              color: const Color(0xFF12151C),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: toLeague.color.withValues(alpha: 0.55),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: toLeague.color.withValues(alpha: 0.25),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      for (final s in _sparkles) _sparkle(s, toLeague.color),
                      Opacity(
                        opacity: badgeOpacity,
                        child: Transform.scale(
                          scale: badgeScale,
                          child: LeagueBadge(league: toLeague, size: 108),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Opacity(
                  opacity: titleT,
                  child: Transform.translate(
                    offset: Offset(0, (1 - titleT) * 12),
                    child: const Text(
                      "LEAGUE UP!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Opacity(
                  opacity: leaguesT,
                  child: Transform.translate(
                    offset: Offset(0, (1 - leaguesT) * 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fromLeague.name,
                          style: TextStyle(
                            color: fromLeague.color.withValues(alpha: 0.75),
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white38,
                            size: 18,
                          ),
                        ),
                        Text(
                          toLeague.name,
                          style: TextStyle(
                            color: toLeague.color,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Opacity(
                  opacity: leaguesT,
                  child: const Text(
                    "You've been promoted -- keep it up!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 22),
                Opacity(
                  opacity: buttonT,
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: toLeague.color,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        "Awesome!",
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }
}
