import 'package:flutter/material.dart';

/// Campaign world — 25 levels each, teaching a mechanic curriculum.
class WorldInfo {
  final String id;
  final String name;
  final int firstLevel;
  final int lastLevel;
  final Color accent;
  final String defaultMission;

  const WorldInfo({
    required this.id,
    required this.name,
    required this.firstLevel,
    required this.lastLevel,
    required this.accent,
    required this.defaultMission,
  });

  bool contains(int level) => level >= firstLevel && level <= lastLevel;
}

/// All campaign worlds in progression order.
const List<WorldInfo> kWorlds = [
  WorldInfo(
    id: 'gateway',
    name: 'Gateway',
    firstLevel: 1,
    lastLevel: 25,
    accent: Color(0xFF00E5FF),
    defaultMission: 'Restore uplink',
  ),
  WorldInfo(
    id: 'lockdown',
    name: 'The Lock',
    firstLevel: 26,
    lastLevel: 50,
    accent: Color(0xFFFFB020),
    defaultMission: 'Clear the vault',
  ),
  WorldInfo(
    id: 'relay_storm',
    name: 'Relay Storm',
    firstLevel: 51,
    lastLevel: 75,
    accent: Color(0xFF00FF87),
    defaultMission: 'Stabilize relays',
  ),
  WorldInfo(
    id: 'labyrinth',
    name: 'Labyrinth',
    firstLevel: 76,
    lastLevel: 100,
    accent: Color(0xFFB388FF),
    defaultMission: 'Navigate blackout',
  ),
];

/// Per-level mission copy overrides for showcase moments.
const Map<int, String> kLevelMissionOverrides = {
  30: 'Restore Cascade Reactor — First Fork',
  35: 'Trace the spiral uplink',
  40: 'Break the vault seal',
  45: 'Seal Breaker — unlock the core',
  50: 'Boss: Gridlock — restore the hub',
  55: 'Phase Shift — align the relays',
  75: 'Boss: Overload — contain the surge',
  100: 'Boss: Blackout — restore the network',
};

/// Named showcase titles for level select / HUD.
const Map<int, String> kShowcaseLevelNames = {
  30: 'First Fork',
  35: 'The Spiral',
  40: 'The Vault',
  45: 'Seal Breaker',
  50: 'Boss: Gridlock',
  55: 'Phase Shift',
  75: 'Boss: Overload',
  100: 'Boss: Blackout',
};

WorldInfo worldForLevel(int level) {
  for (final w in kWorlds) {
    if (w.contains(level)) return w;
  }
  return kWorlds.last;
}

String missionForLevel(int level) =>
    kLevelMissionOverrides[level] ?? worldForLevel(level).defaultMission;

String? showcaseNameForLevel(int level) => kShowcaseLevelNames[level];

bool isBossLevel(int level) => level > 0 && level % 25 == 0;

/// HUD label, e.g. `THE LOCK · 38`.
String worldHudLabel(int level) {
  final world = worldForLevel(level);
  final name = showcaseNameForLevel(level);
  if (name != null) return '${world.name.toUpperCase()} · $name';
  return '${world.name.toUpperCase()} · $level';
}
