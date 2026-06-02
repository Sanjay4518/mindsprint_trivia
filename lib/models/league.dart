import 'package:flutter/material.dart';

class League {
  final String name;
  final int minXp;
  final int? maxXp;
  final Color color;
  final IconData icon;

  const League({
    required this.name,
    required this.minXp,
    required this.maxXp,
    required this.color,
    required this.icon,
  });

  bool containsXp(int xp) {
    if (xp < minXp) return false;
    final upperBound = maxXp;
    return upperBound == null || xp < upperBound;
  }
}
