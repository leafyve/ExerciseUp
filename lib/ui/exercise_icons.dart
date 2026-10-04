import 'package:flutter/material.dart';

/// Icon choices for exercises. Stored by key so the DB never holds codepoints.
const exerciseIcons = <String, IconData>{
  'pushup': Icons.fitness_center,
  'squat': Icons.accessibility_new,
  'situp': Icons.self_improvement,
  'plank': Icons.timer_outlined,
  'lunge': Icons.directions_walk,
  'jack': Icons.sports_gymnastics,
  'burpee': Icons.bolt,
  'fitness': Icons.sports_martial_arts,
  'run': Icons.directions_run,
  'bike': Icons.directions_bike,
  'stretch': Icons.spa_outlined,
  'heart': Icons.favorite_border,
};

IconData iconFor(String key) => exerciseIcons[key] ?? Icons.fitness_center;
