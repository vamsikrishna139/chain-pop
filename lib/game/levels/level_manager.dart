import 'package:flutter/material.dart';
import 'level.dart';
import 'generation/generation.dart';

/// Thin adapter that bridges the game engine (which expects a simple
/// `LevelData`) with the [LevelGenerator] Result-based API.
///
/// The manager resolves generation results and always returns a valid
/// [LevelData] — either the generated level or a safe fallback.
class LevelManager {
  static final LevelGenerator _generator = LevelGenerator();

  /// Returns a valid, solvable [LevelData] for [levelId].
  ///
  /// Uses the full generation pipeline from [LevelGenerator]. If generation
  /// fails for any reason (e.g. invalid configuration), a guaranteed-solvable
  /// fallback is returned rather than throwing.
  static LevelData getLevel(int levelId, {DifficultyMode? mode}) {
    final result = _generator.generate(levelId, mode: mode);

    if (result.isSuccess) {
      return result.value;
    }

    // Log error and use emergency fallback (a single-node level is always
    // solvable and prevents any crash from reaching the player).
    assert(false, 'Level generation failed: ${result.error}');
    return _emergencyFallback(levelId);
  }

  /// An absolute last-resort fallback: one node pointing up in an empty grid.
  static LevelData _emergencyFallback(int levelId) {
    return LevelData(
      levelId: levelId,
      gridWidth: 4,
      gridHeight: 4,
      nodes: [
        NodeData(
          id: 0,
          x: 1,
          y: 3,
          dir: Direction.up,
          color: const Color(0xFF4FACFE),
        ),
      ],
    );
  }
}
