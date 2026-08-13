import 'package:flutter/material.dart';

class SectorInfo {
  final String name;
  final String paletteFamily;
  final int mechanicBudgetTier;

  const SectorInfo({
    required this.name,
    required this.paletteFamily,
    required this.mechanicBudgetTier,
  });
}

class WorldInfo {
  final String id;
  final String name;
  final int firstLevel;
  final int lastLevel;
  final Color accent;
  final String defaultMission;
  final SectorInfo sector;

  const WorldInfo({
    required this.id,
    required this.name,
    required this.firstLevel,
    required this.lastLevel,
    required this.accent,
    required this.defaultMission,
    required this.sector,
  });

  bool contains(int level) => level >= firstLevel && level <= lastLevel;
}

const List<SectorInfo> kSectors = [
  SectorInfo(name: 'Sector 1', paletteFamily: 'family1', mechanicBudgetTier: 1),
  SectorInfo(name: 'Sector 2', paletteFamily: 'family2', mechanicBudgetTier: 2),
  SectorInfo(name: 'Sector 3', paletteFamily: 'family3', mechanicBudgetTier: 3),
  SectorInfo(name: 'Sector 4', paletteFamily: 'family4', mechanicBudgetTier: 4),
  SectorInfo(name: 'Sector 5', paletteFamily: 'family5', mechanicBudgetTier: 5),
  SectorInfo(name: 'Sector 6', paletteFamily: 'family6', mechanicBudgetTier: 6),
  SectorInfo(name: 'Sector 7', paletteFamily: 'family7', mechanicBudgetTier: 7),
  SectorInfo(name: 'Sector 8', paletteFamily: 'family8', mechanicBudgetTier: 8),
];

final List<WorldInfo> kWorlds = [
  WorldInfo(
    id: 'gateway',
    name: 'Gateway',
    firstLevel: 1,
    lastLevel: 25,
    accent: const Color(0xFF00E5FF),
    defaultMission: 'Restore uplink',
    sector: kSectors[0],
  ),
  WorldInfo(
    id: 'lockdown',
    name: 'The Lock',
    firstLevel: 26,
    lastLevel: 50,
    accent: const Color(0xFF00E5FF),
    defaultMission: 'Clear the vault',
    sector: kSectors[0],
  ),
  WorldInfo(
    id: 'relay_storm',
    name: 'Relay Storm',
    firstLevel: 51,
    lastLevel: 75,
    accent: const Color(0xFF00E5FF),
    defaultMission: 'Stabilize relays',
    sector: kSectors[0],
  ),
  WorldInfo(
    id: 'labyrinth',
    name: 'Labyrinth',
    firstLevel: 76,
    lastLevel: 100,
    accent: const Color(0xFF00E5FF),
    defaultMission: 'Navigate blackout',
    sector: kSectors[0],
  ),
  WorldInfo(
    id: 'world_5',
    name: 'World 5',
    firstLevel: 101,
    lastLevel: 125,
    accent: const Color(0xFF00E5FF),
    defaultMission: 'Clear sector 1',
    sector: kSectors[0],
  ),
  WorldInfo(
    id: 'world_6',
    name: 'World 6',
    firstLevel: 126,
    lastLevel: 150,
    accent: const Color(0xFFFFB020),
    defaultMission: 'Clear sector 2',
    sector: kSectors[1],
  ),
  WorldInfo(
    id: 'world_7',
    name: 'World 7',
    firstLevel: 151,
    lastLevel: 175,
    accent: const Color(0xFFFFB020),
    defaultMission: 'Clear sector 2',
    sector: kSectors[1],
  ),
  WorldInfo(
    id: 'world_8',
    name: 'World 8',
    firstLevel: 176,
    lastLevel: 200,
    accent: const Color(0xFFFFB020),
    defaultMission: 'Clear sector 2',
    sector: kSectors[1],
  ),
  WorldInfo(
    id: 'world_9',
    name: 'World 9',
    firstLevel: 201,
    lastLevel: 225,
    accent: const Color(0xFFFFB020),
    defaultMission: 'Clear sector 2',
    sector: kSectors[1],
  ),
  WorldInfo(
    id: 'world_10',
    name: 'World 10',
    firstLevel: 226,
    lastLevel: 250,
    accent: const Color(0xFFFFB020),
    defaultMission: 'Clear sector 2',
    sector: kSectors[1],
  ),
  WorldInfo(
    id: 'world_11',
    name: 'World 11',
    firstLevel: 251,
    lastLevel: 275,
    accent: const Color(0xFF00FF87),
    defaultMission: 'Clear sector 3',
    sector: kSectors[2],
  ),
  WorldInfo(
    id: 'world_12',
    name: 'World 12',
    firstLevel: 276,
    lastLevel: 300,
    accent: const Color(0xFF00FF87),
    defaultMission: 'Clear sector 3',
    sector: kSectors[2],
  ),
  WorldInfo(
    id: 'world_13',
    name: 'World 13',
    firstLevel: 301,
    lastLevel: 325,
    accent: const Color(0xFF00FF87),
    defaultMission: 'Clear sector 3',
    sector: kSectors[2],
  ),
  WorldInfo(
    id: 'world_14',
    name: 'World 14',
    firstLevel: 326,
    lastLevel: 350,
    accent: const Color(0xFF00FF87),
    defaultMission: 'Clear sector 3',
    sector: kSectors[2],
  ),
  WorldInfo(
    id: 'world_15',
    name: 'World 15',
    firstLevel: 351,
    lastLevel: 375,
    accent: const Color(0xFF00FF87),
    defaultMission: 'Clear sector 3',
    sector: kSectors[2],
  ),
  WorldInfo(
    id: 'world_16',
    name: 'World 16',
    firstLevel: 376,
    lastLevel: 400,
    accent: const Color(0xFFB388FF),
    defaultMission: 'Clear sector 4',
    sector: kSectors[3],
  ),
  WorldInfo(
    id: 'world_17',
    name: 'World 17',
    firstLevel: 401,
    lastLevel: 425,
    accent: const Color(0xFFB388FF),
    defaultMission: 'Clear sector 4',
    sector: kSectors[3],
  ),
  WorldInfo(
    id: 'world_18',
    name: 'World 18',
    firstLevel: 426,
    lastLevel: 450,
    accent: const Color(0xFFB388FF),
    defaultMission: 'Clear sector 4',
    sector: kSectors[3],
  ),
  WorldInfo(
    id: 'world_19',
    name: 'World 19',
    firstLevel: 451,
    lastLevel: 475,
    accent: const Color(0xFFB388FF),
    defaultMission: 'Clear sector 4',
    sector: kSectors[3],
  ),
  WorldInfo(
    id: 'world_20',
    name: 'World 20',
    firstLevel: 476,
    lastLevel: 500,
    accent: const Color(0xFFB388FF),
    defaultMission: 'Clear sector 4',
    sector: kSectors[3],
  ),
  WorldInfo(
    id: 'world_21',
    name: 'World 21',
    firstLevel: 501,
    lastLevel: 525,
    accent: const Color(0xFFFF3D00),
    defaultMission: 'Clear sector 5',
    sector: kSectors[4],
  ),
  WorldInfo(
    id: 'world_22',
    name: 'World 22',
    firstLevel: 526,
    lastLevel: 550,
    accent: const Color(0xFFFF3D00),
    defaultMission: 'Clear sector 5',
    sector: kSectors[4],
  ),
  WorldInfo(
    id: 'world_23',
    name: 'World 23',
    firstLevel: 551,
    lastLevel: 575,
    accent: const Color(0xFFFF3D00),
    defaultMission: 'Clear sector 5',
    sector: kSectors[4],
  ),
  WorldInfo(
    id: 'world_24',
    name: 'World 24',
    firstLevel: 576,
    lastLevel: 600,
    accent: const Color(0xFFFF3D00),
    defaultMission: 'Clear sector 5',
    sector: kSectors[4],
  ),
  WorldInfo(
    id: 'world_25',
    name: 'World 25',
    firstLevel: 601,
    lastLevel: 625,
    accent: const Color(0xFFFF3D00),
    defaultMission: 'Clear sector 5',
    sector: kSectors[4],
  ),
  WorldInfo(
    id: 'world_26',
    name: 'World 26',
    firstLevel: 626,
    lastLevel: 650,
    accent: const Color(0xFFFF4081),
    defaultMission: 'Clear sector 6',
    sector: kSectors[5],
  ),
  WorldInfo(
    id: 'world_27',
    name: 'World 27',
    firstLevel: 651,
    lastLevel: 675,
    accent: const Color(0xFFFF4081),
    defaultMission: 'Clear sector 6',
    sector: kSectors[5],
  ),
  WorldInfo(
    id: 'world_28',
    name: 'World 28',
    firstLevel: 676,
    lastLevel: 700,
    accent: const Color(0xFFFF4081),
    defaultMission: 'Clear sector 6',
    sector: kSectors[5],
  ),
  WorldInfo(
    id: 'world_29',
    name: 'World 29',
    firstLevel: 701,
    lastLevel: 725,
    accent: const Color(0xFFFF4081),
    defaultMission: 'Clear sector 6',
    sector: kSectors[5],
  ),
  WorldInfo(
    id: 'world_30',
    name: 'World 30',
    firstLevel: 726,
    lastLevel: 750,
    accent: const Color(0xFFFF4081),
    defaultMission: 'Clear sector 6',
    sector: kSectors[5],
  ),
  WorldInfo(
    id: 'world_31',
    name: 'World 31',
    firstLevel: 751,
    lastLevel: 775,
    accent: const Color(0xFF1DE9B6),
    defaultMission: 'Clear sector 7',
    sector: kSectors[6],
  ),
  WorldInfo(
    id: 'world_32',
    name: 'World 32',
    firstLevel: 776,
    lastLevel: 800,
    accent: const Color(0xFF1DE9B6),
    defaultMission: 'Clear sector 7',
    sector: kSectors[6],
  ),
  WorldInfo(
    id: 'world_33',
    name: 'World 33',
    firstLevel: 801,
    lastLevel: 825,
    accent: const Color(0xFF1DE9B6),
    defaultMission: 'Clear sector 7',
    sector: kSectors[6],
  ),
  WorldInfo(
    id: 'world_34',
    name: 'World 34',
    firstLevel: 826,
    lastLevel: 850,
    accent: const Color(0xFF1DE9B6),
    defaultMission: 'Clear sector 7',
    sector: kSectors[6],
  ),
  WorldInfo(
    id: 'world_35',
    name: 'World 35',
    firstLevel: 851,
    lastLevel: 875,
    accent: const Color(0xFF1DE9B6),
    defaultMission: 'Clear sector 7',
    sector: kSectors[6],
  ),
  WorldInfo(
    id: 'world_36',
    name: 'World 36',
    firstLevel: 876,
    lastLevel: 900,
    accent: const Color(0xFFD50000),
    defaultMission: 'Clear sector 8',
    sector: kSectors[7],
  ),
  WorldInfo(
    id: 'world_37',
    name: 'World 37',
    firstLevel: 901,
    lastLevel: 925,
    accent: const Color(0xFFD50000),
    defaultMission: 'Clear sector 8',
    sector: kSectors[7],
  ),
  WorldInfo(
    id: 'world_38',
    name: 'World 38',
    firstLevel: 926,
    lastLevel: 950,
    accent: const Color(0xFFD50000),
    defaultMission: 'Clear sector 8',
    sector: kSectors[7],
  ),
  WorldInfo(
    id: 'world_39',
    name: 'World 39',
    firstLevel: 951,
    lastLevel: 975,
    accent: const Color(0xFFD50000),
    defaultMission: 'Clear sector 8',
    sector: kSectors[7],
  ),
  WorldInfo(
    id: 'world_40',
    name: 'World 40',
    firstLevel: 976,
    lastLevel: 1000,
    accent: const Color(0xFFD50000),
    defaultMission: 'Clear sector 8',
    sector: kSectors[7],
  ),
];

final Map<int, String> kLevelMissionOverrides = {
  25: 'Boss: Guardian 1 — restore the network',
  50: 'Boss: Gridlock — restore the hub',
  75: 'Boss: Overload — contain the surge',
  100: 'Boss: Blackout — restore the network',
  125: 'Boss: Guardian 5 — restore the network',
  150: 'Boss: Guardian 6 — restore the network',
  175: 'Boss: Guardian 7 — restore the network',
  200: 'Boss: Guardian 8 — restore the network',
  225: 'Boss: Guardian 9 — restore the network',
  250: 'Boss: Guardian 10 — restore the network',
  275: 'Boss: Guardian 11 — restore the network',
  300: 'Boss: Guardian 12 — restore the network',
  325: 'Boss: Guardian 13 — restore the network',
  350: 'Boss: Guardian 14 — restore the network',
  375: 'Boss: Guardian 15 — restore the network',
  400: 'Boss: Guardian 16 — restore the network',
  425: 'Boss: Guardian 17 — restore the network',
  450: 'Boss: Guardian 18 — restore the network',
  475: 'Boss: Guardian 19 — restore the network',
  500: 'Boss: Guardian 20 — restore the network',
  525: 'Boss: Guardian 21 — restore the network',
  550: 'Boss: Guardian 22 — restore the network',
  575: 'Boss: Guardian 23 — restore the network',
  600: 'Boss: Guardian 24 — restore the network',
  625: 'Boss: Guardian 25 — restore the network',
  650: 'Boss: Guardian 26 — restore the network',
  675: 'Boss: Guardian 27 — restore the network',
  700: 'Boss: Guardian 28 — restore the network',
  725: 'Boss: Guardian 29 — restore the network',
  750: 'Boss: Guardian 30 — restore the network',
  775: 'Boss: Guardian 31 — restore the network',
  800: 'Boss: Guardian 32 — restore the network',
  825: 'Boss: Guardian 33 — restore the network',
  850: 'Boss: Guardian 34 — restore the network',
  875: 'Boss: Guardian 35 — restore the network',
  900: 'Boss: Guardian 36 — restore the network',
  925: 'Boss: Guardian 37 — restore the network',
  950: 'Boss: Guardian 38 — restore the network',
  975: 'Boss: Guardian 39 — restore the network',
  1000: 'Boss: Guardian 40 — restore the network',
  30: 'Restore Cascade Reactor — First Fork',
  35: 'Trace the spiral uplink',
  40: 'Break the vault seal',
  45: 'Seal Breaker — unlock the core',
  55: 'Phase Shift — align the relays',
};

final Map<int, String> kShowcaseLevelNames = {
  25: 'Boss: Guardian 1',
  50: 'Boss: Gridlock',
  75: 'Boss: Overload',
  100: 'Boss: Blackout',
  125: 'Boss: Guardian 5',
  150: 'Boss: Guardian 6',
  175: 'Boss: Guardian 7',
  200: 'Boss: Guardian 8',
  225: 'Boss: Guardian 9',
  250: 'Boss: Guardian 10',
  275: 'Boss: Guardian 11',
  300: 'Boss: Guardian 12',
  325: 'Boss: Guardian 13',
  350: 'Boss: Guardian 14',
  375: 'Boss: Guardian 15',
  400: 'Boss: Guardian 16',
  425: 'Boss: Guardian 17',
  450: 'Boss: Guardian 18',
  475: 'Boss: Guardian 19',
  500: 'Boss: Guardian 20',
  525: 'Boss: Guardian 21',
  550: 'Boss: Guardian 22',
  575: 'Boss: Guardian 23',
  600: 'Boss: Guardian 24',
  625: 'Boss: Guardian 25',
  650: 'Boss: Guardian 26',
  675: 'Boss: Guardian 27',
  700: 'Boss: Guardian 28',
  725: 'Boss: Guardian 29',
  750: 'Boss: Guardian 30',
  775: 'Boss: Guardian 31',
  800: 'Boss: Guardian 32',
  825: 'Boss: Guardian 33',
  850: 'Boss: Guardian 34',
  875: 'Boss: Guardian 35',
  900: 'Boss: Guardian 36',
  925: 'Boss: Guardian 37',
  950: 'Boss: Guardian 38',
  975: 'Boss: Guardian 39',
  1000: 'Boss: Guardian 40',
  30: 'First Fork',
  35: 'The Spiral',
  40: 'The Vault',
  45: 'Seal Breaker',
  55: 'Phase Shift',
};

WorldInfo worldForLevel(int level) {
  if (level <= 1000) {
    for (final w in kWorlds) {
      if (w.contains(level)) return w;
    }
  }
  final normalized = ((level - 1) % 1000) + 1;
  final prestige = (level - 1) ~/ 1000;
  final baseWorld = kWorlds.firstWhere((w) => w.contains(normalized));
  return WorldInfo(
    id: '${baseWorld.id}_p$prestige',
    name: '${baseWorld.name} +$prestige',
    firstLevel: baseWorld.firstLevel + prestige * 1000,
    lastLevel: baseWorld.lastLevel + prestige * 1000,
    accent: baseWorld.accent,
    defaultMission: baseWorld.defaultMission,
    sector: baseWorld.sector,
  );
}

String missionForLevel(int level) =>
    kLevelMissionOverrides[level] ?? worldForLevel(level).defaultMission;

/// Head of the mission line, dropping the em-dash tail that boss overrides use
/// ("Boss: Guardian 40 — restore the network" -> "Boss: Guardian 40"). The HUD
/// gives this ~130px; the full string stays for level select / world intro.
String missionShortForLevel(int level) {
  final full = missionForLevel(level);
  final i = full.indexOf(' — ');
  return i < 0 ? full : full.substring(0, i);
}

String? showcaseNameForLevel(int level) {
  final normalized = level <= 1000 ? level : ((level - 1) % 1000) + 1;
  return kShowcaseLevelNames[normalized];
}

bool isBossLevel(int level) => level > 0 && level % 25 == 0;

String worldHudLabel(int level) {
  final world = worldForLevel(level);
  final name = showcaseNameForLevel(level);
  if (name != null) return '${world.name.toUpperCase()} · $name';
  return '${world.name.toUpperCase()} · $level';
}

