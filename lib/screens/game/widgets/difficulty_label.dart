import 'package:flutter/material.dart';

import '../../../game/levels/generation/difficulty_mode.dart';
import '../../../models/difficulty.dart';

class DifficultyLabel extends StatelessWidget {
  final DifficultyMode difficulty;

  const DifficultyLabel({super.key, required this.difficulty});

  @override
  Widget build(BuildContext context) {
    return Text(
      difficulty.label.toUpperCase(),
      style: TextStyle(
        color: difficulty.color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.2,
      ),
    );
  }
}
