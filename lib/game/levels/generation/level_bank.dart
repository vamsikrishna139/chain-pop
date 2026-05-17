import 'dart:convert';

import '../level.dart';
import 'map_elites.dart';

/// Runtime loader for the §4.6 / Phase 7 MAP-Elites archive.
///
/// The bank itself is built **offline** (`tools/map_elites_runner.dart`)
/// and shipped as a JSON asset under `assets/level_banks/`. This class is
/// the runtime-side: it parses the JSON, exposes the archive, and answers
/// `pickForDailyKey` / `pickForCell` queries from Daily / Specials.
///
/// Format (`map_elites_v1.json`):
/// ```json
/// {
///   "version": 1,
///   "feature": "(waveDepth, avgBranchingFactor)",
///   "entries": [
///     { "wave": 4, "bf": 2, "quality": 0.81,
///       "level": { "levelId": 1042, "gridWidth": 8, "gridHeight": 8,
///                   "nodes": [ { "id":0, "x":3,"y":2,"dir":"up" }, ... ],
///                   "playCells": ["3,2", "4,2", ...] } },
///     ...
///   ]
/// }
/// ```
class LevelBank {
  final MapElitesArchive archive;
  const LevelBank({required this.archive});

  factory LevelBank.empty() =>
      LevelBank(archive: MapElitesArchive.empty(version: 1));

  /// Parses [jsonString] (`map_elites_vN.json` payload) and returns a bank.
  /// Throws `FormatException` if the payload is corrupt; callers can fall
  /// back to [LevelBank.empty] in that case.
  factory LevelBank.fromJsonString(String jsonString) {
    final raw = json.decode(jsonString);
    if (raw is! Map<String, Object?>) {
      throw const FormatException('LevelBank: top-level must be a JSON object');
    }
    final version = raw['version'];
    if (version is! int) {
      throw const FormatException('LevelBank: missing or invalid "version"');
    }
    final entriesRaw = raw['entries'];
    if (entriesRaw is! List) {
      throw const FormatException('LevelBank: "entries" must be a list');
    }
    final entries = <MapElitesEntry>[
      for (final e in entriesRaw)
        _decodeEntry(e as Map<String, Object?>),
    ];
    return LevelBank(
      archive: MapElitesArchive.fromEntries(entries, version: version),
    );
  }

  /// Daily — pick a deterministic entry from the archive for [dayKey].
  /// Returns null when the bank is empty.
  LevelData? pickForDailyKey(int dayKey) =>
      archive.pickForDailyKey(dayKey)?.level;

  /// Coverage convenience for the Phase-7 acceptance criterion.
  double get coverage => archive.coverage;

  static MapElitesEntry _decodeEntry(Map<String, Object?> raw) {
    final wave = raw['wave'] as int;
    final bf = raw['bf'] as int;
    final quality = (raw['quality'] as num).toDouble();
    final level = _decodeLevel(raw['level'] as Map<String, Object?>);
    return MapElitesEntry(
      waveBucket: wave,
      bfBucket: bf,
      qualityScore: quality,
      level: level,
    );
  }

  static LevelData _decodeLevel(Map<String, Object?> raw) {
    final levelId = raw['levelId'] as int;
    final gridWidth = raw['gridWidth'] as int;
    final gridHeight = raw['gridHeight'] as int;
    final nodesRaw = raw['nodes'] as List;
    final nodes = <NodeData>[
      for (final n in nodesRaw)
        _decodeNode(n as Map<String, Object?>),
    ];
    Set<String>? playCells;
    final playRaw = raw['playCells'];
    if (playRaw is List) {
      playCells = playRaw.map((e) => e.toString()).toSet();
    }
    return LevelData(
      levelId: levelId,
      gridWidth: gridWidth,
      gridHeight: gridHeight,
      nodes: nodes,
      playCells: playCells,
    );
  }

  static NodeData _decodeNode(Map<String, Object?> raw) {
    final id = raw['id'] as int;
    final x = raw['x'] as int;
    final y = raw['y'] as int;
    final dirName = raw['dir'] as String;
    final dir = Direction.values.firstWhere(
      (d) => d.name == dirName,
      orElse: () => throw FormatException('Unknown direction: $dirName'),
    );
    return NodeData(id: id, x: x, y: y, dir: dir);
  }
}

/// Serialises an archive to the v1 JSON payload above. Used by
/// `tools/map_elites_runner.dart` (offline) and the round-trip tests.
String encodeMapElitesArchive(MapElitesArchive archive) {
  final payload = <String, Object?>{
    'version': archive.version,
    'feature': '(waveDepth, avgBranchingFactor)',
    'entries': [
      for (final e in archive.entries)
        <String, Object?>{
          'wave': e.waveBucket,
          'bf': e.bfBucket,
          'quality': e.qualityScore,
          'level': _encodeLevel(e.level),
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(payload);
}

Map<String, Object?> _encodeLevel(LevelData level) {
  return <String, Object?>{
    'levelId': level.levelId,
    'gridWidth': level.gridWidth,
    'gridHeight': level.gridHeight,
    'nodes': [
      for (final n in level.nodes)
        <String, Object?>{
          'id': n.id,
          'x': n.x,
          'y': n.y,
          'dir': n.dir.name,
        },
    ],
    if (level.playCells != null) 'playCells': level.playCells!.toList()..sort(),
  };
}
