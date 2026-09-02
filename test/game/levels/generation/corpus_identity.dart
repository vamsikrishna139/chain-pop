// Deterministic corpus fingerprinting — the "did any board move?" instrument.
//
// Every phase from T0 onward has to answer that question. An aggregate hash
// alone answers it with a yes/no and nothing else, which is useless the moment
// the answer is "yes" and you need to know *which* board and *how*. So this
// records the population size and byte length alongside the hash, and can
// report the FIRST differing board field-by-field.
//
// P1 moves no geometry and P2 moves it deliberately; in both cases the useful
// output is the same — the first mismatch, named.
import 'dart:convert';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/generation/level_generator.dart';
import 'package:chain_pop/game/levels/level.dart';

/// One board reduced to the fields that define its identity.
class BoardIdentity {
  BoardIdentity({
    required this.levelId,
    required this.mode,
    required this.gridWidth,
    required this.gridHeight,
    required this.nodeCount,
    required this.nodeLines,
  });

  final int levelId;
  final DifficultyMode mode;
  final int gridWidth;
  final int gridHeight;
  final int nodeCount;

  /// `id,x,y,dir,isCore,kind` per node, in emission order.
  final List<String> nodeLines;

  String get key => '$levelId/${mode.name}';

  String get header => '$key/${gridWidth}x$gridHeight/$nodeCount';

  static BoardIdentity of(LevelData level, DifficultyMode mode) =>
      BoardIdentity(
        levelId: level.levelId,
        mode: mode,
        gridWidth: level.gridWidth,
        gridHeight: level.gridHeight,
        nodeCount: level.nodes.length,
        nodeLines: [
          for (final n in level.nodes)
            '${n.id},${n.x},${n.y},${n.dir.name},${n.isCore},${n.kind.name}',
        ],
      );

  /// The first field that differs from [other], or null when identical.
  String? firstDifference(BoardIdentity other) {
    if (gridWidth != other.gridWidth || gridHeight != other.gridHeight) {
      return 'grid ${gridWidth}x$gridHeight vs '
          '${other.gridWidth}x${other.gridHeight}';
    }
    if (nodeCount != other.nodeCount) {
      return 'nodeCount $nodeCount vs ${other.nodeCount}';
    }
    for (var i = 0; i < nodeLines.length; i++) {
      if (nodeLines[i] != other.nodeLines[i]) {
        return 'node[$i] "${nodeLines[i]}" vs "${other.nodeLines[i]}"';
      }
    }
    return null;
  }
}

/// A whole corpus, fingerprinted.
class CorpusFingerprint {
  CorpusFingerprint({
    required this.boards,
    required this.byteLength,
    required this.hash,
    required this.identities,
  });

  /// Number of boards generated — guards against a sweep that silently
  /// shrank, which a hash comparison alone would report as a clean failure.
  final int boards;

  /// Total bytes of the serialised corpus.
  final int byteLength;

  /// FNV-1a 64 over the serialised corpus.
  final String hash;

  final List<BoardIdentity> identities;

  String get summary => 'boards=$boards bytes=$byteLength hash=$hash';

  /// The first board that differs from [other], described, or null when the
  /// two corpora are identical. Reports population mismatch first.
  String? firstMismatch(CorpusFingerprint other) {
    if (boards != other.boards) {
      return 'corpus size differs: $boards vs ${other.boards} boards';
    }
    for (var i = 0; i < identities.length; i++) {
      final a = identities[i];
      final b = other.identities[i];
      if (a.key != b.key)
        return 'board order differs at $i: ${a.key} vs ${b.key}';
      final diff = a.firstDifference(b);
      if (diff != null) return '${a.key}: $diff';
    }
    return null;
  }

  /// Generates [levelIds] × [modes] and fingerprints the result.
  ///
  /// Always uses `LevelGenerator.neutral()` and **never** a time budget: the
  /// determinism contract only holds with `timeBudget == null` (see
  /// `docs/playtests/generator_input_closure.md`, "Wall-clock is an input on
  /// the budgeted path"). A budgeted fingerprint would drift run to run and
  /// the instrument would be worthless.
  static CorpusFingerprint generate({
    required List<int> levelIds,
    List<DifficultyMode> modes = DifficultyMode.values,
  }) {
    final buffer = StringBuffer();
    final identities = <BoardIdentity>[];
    for (final mode in modes) {
      for (final id in levelIds) {
        final result = LevelGenerator.neutral().generate(id, mode: mode);
        if (!result.isSuccess) {
          throw StateError('generation failed for $id/${mode.name}');
        }
        final identity = BoardIdentity.of(result.value, mode);
        identities.add(identity);
        buffer.writeln(identity.header);
        for (final line in identity.nodeLines) {
          buffer.writeln(line);
        }
      }
    }
    final bytes = utf8.encode(buffer.toString());
    var h = 0xcbf29ce484222325;
    for (final byte in bytes) {
      h ^= byte;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return CorpusFingerprint(
      boards: identities.length,
      byteLength: bytes.length,
      hash: h.toRadixString(16),
      identities: identities,
    );
  }
}
