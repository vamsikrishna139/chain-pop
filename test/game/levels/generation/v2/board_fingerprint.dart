import 'package:chain_pop/game/levels/level.dart';

/// Stable text fingerprint of everything a player sees and plays on a board.
/// Used by the Gen V2 gates to prove V1 boards never move.
String boardFingerprint(LevelData l) {
  final nodes = [...l.nodes]..sort((a, b) => a.id.compareTo(b.id));
  final cells = l.playCells == null ? 'full' : ([...l.playCells!]..sort()).join(';');
  final ns = nodes
      .map((n) =>
          '${n.id}:${n.x},${n.y},${n.dir.name},${n.kind.name},${n.isCore ? 1 : 0},${n.phaseGroup}')
      .join('|');
  final ps = l.portalPairs.map((p) => '${p.x1},${p.y1}-${p.x2},${p.y2}').join('|');
  return '${l.gridWidth}x${l.gridHeight}#$cells#$ns#$ps';
}

/// FNV-1a 64-bit (truncated to 53 bits so it round-trips as a JSON number).
int fingerprintHash(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  return h & 0x1FFFFFFFFFFFFF;
}
