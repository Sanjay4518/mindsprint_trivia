import 'package:flutter/material.dart';
import '../models/league.dart';

class LeagueBadge extends StatelessWidget {
  final League league;
  final double size;
  final bool showLabel;

  const LeagueBadge({
    super.key,
    required this.league,
    this.size = 54,
    this.showLabel = false,
  });

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: league.color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
        border: Border.all(color: league.color.withValues(alpha: 0.75)),
        boxShadow: [
          BoxShadow(
            color: league.color.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(league.icon, color: league.color, size: size * 0.48),
    );

    if (!showLabel) return badge;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        badge,
        const SizedBox(height: 8),
        Text(
          league.name,
          style: TextStyle(
            color: league.color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class LeagueProgressCard extends StatelessWidget {
  final League currentLeague;
  final League? nextLeague;
  final double progress;
  final int xpToNextLeague;
  final int totalXp;
  final EdgeInsetsGeometry padding;

  const LeagueProgressCard({
    super.key,
    required this.currentLeague,
    required this.nextLeague,
    required this.progress,
    required this.xpToNextLeague,
    required this.totalXp,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    final isMaxLeague = nextLeague == null;
    final percent = (progress * 100).round();

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xFF181C24),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: currentLeague.color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              LeagueBadge(league: currentLeague, size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Current League",
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      currentLeague.name,
                      style: TextStyle(
                        color: currentLeague.color,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                "$totalXp XP",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: const Color(0xFF2B3242),
              valueColor: AlwaysStoppedAnimation<Color>(currentLeague.color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                "$percent%",
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  isMaxLeague
                      ? "Highest league reached"
                      : "$xpToNextLeague XP to ${nextLeague!.name}",
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
