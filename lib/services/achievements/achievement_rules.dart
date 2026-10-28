import '../../game/levels/level_directive.dart';
import 'achievement_catalog.dart';
import 'achievement_stats.dart';

/// Current local progress for one achievement, given a stats snapshot.
typedef AchievementProgressFn = int Function(AchievementStats stats);

int _clamp(int v, int max) => v < 0 ? 0 : (v > max ? max : v);

int _flag(AchievementStats s, int flag) => s.hasFlag(flag) ? 1 : 0;

int _directive(AchievementStats s, LevelDirective d) =>
    s.hasDirective(d) ? 1 : 0;

/// Progress rule per [AchievementDef.id].
///
/// Every entry in [kAchievementCatalog] must appear here — `achievement_rules_test`
/// asserts the two sets match exactly, so adding a catalog entry without a rule
/// is a test failure rather than an achievement that can never unlock.
///
/// Rules are pure functions of [AchievementStats]. They are evaluated after
/// every event, so they must stay cheap: read fields, do arithmetic, return.
final Map<String, AchievementProgressFn> kAchievementRules =
    <String, AchievementProgressFn>{
  // ── A · First hour ────────────────────────────────────────────────────────
  // `highestUnlocked` is the frontier, so "cleared level N" is `frontier > N`.
  AchievementIds.coldStart: (s) => s.highestLevelAnyMode >= 2 ? 1 : 0,
  AchievementIds.findingFooting: (s) => _clamp(s.highestLevelAnyMode, 10),
  AchievementIds.hundredDown: (s) => _clamp(s.nodesCleared, 100),
  AchievementIds.firstGuardian: (s) => s.highestLevelAnyMode >= 26 ? 1 : 0,

  // ── B · Depth ─────────────────────────────────────────────────────────────
  AchievementIds.journeyBegun: (s) => _clamp(s.highestLevelAnyMode, 50),
  AchievementIds.century: (s) => _clamp(s.highestLevelAnyMode, 100),
  AchievementIds.deepRun: (s) => _clamp(s.highestLevelAnyMode, 250),
  AchievementIds.halfwayHome: (s) => _clamp(s.highestLevelAnyMode, 500),
  AchievementIds.finalApproach: (s) => _clamp(s.highestLevelAnyMode, 750),
  // "Clear level 1,000" — one past the others, so count cleared levels.
  AchievementIds.guardian40: (s) => _clamp(s.highestLevelAnyMode - 1, 1000),

  // ── C · All three tracks ──────────────────────────────────────────────────
  AchievementIds.threeFronts: (s) => _clamp(s.modesAtLevel50, 3),
  AchievementIds.tripleThreat: (s) => _clamp(s.modesAtLevel200, 3),

  // ── D · Stars ─────────────────────────────────────────────────────────────
  AchievementIds.risingStar: (s) => _clamp(s.totalStars, 100),
  AchievementIds.starCollector: (s) => _clamp(s.totalStars, 500),
  AchievementIds.constellation: (s) => _clamp(s.totalStars, 1500),
  AchievementIds.galaxy: (s) => _clamp(s.totalStars, 3000),

  // ── E · Volume ────────────────────────────────────────────────────────────
  AchievementIds.nodeRunner: (s) => _clamp(s.nodesCleared, 1000),
  AchievementIds.nodeKnight: (s) => _clamp(s.nodesCleared, 10000),
  AchievementIds.nodeLord: (s) => _clamp(s.nodesCleared, 50000),
  AchievementIds.nodeLegend: (s) => _clamp(s.nodesCleared, 150000),

  // ── F · Mechanics ─────────────────────────────────────────────────────────
  AchievementIds.coreCollector: (s) => _clamp(s.coresExtracted, 100),
  AchievementIds.locksmith: (s) => _clamp(s.locksOpened, 50),
  AchievementIds.relayRunner: (s) => _clamp(s.relaysCleared, 50),
  AchievementIds.phaseShift: (s) => _clamp(s.phaseGatesCleared, 50),
  AchievementIds.portalHopper: (s) => _clamp(s.portalsTraversed, 50),

  // ── G · Guardians ─────────────────────────────────────────────────────────
  AchievementIds.guardianHunter: (s) => _clamp(s.guardiansCleared, 10),
  AchievementIds.guardianPerfect: (s) =>
      _flag(s, AchievementFlag.guardianPerfect),
  AchievementIds.sectorClean: (s) =>
      _clamp(s.bestSectorGuardiansThreeStarred, 5),

  // ── H · Directives ────────────────────────────────────────────────────────
  AchievementIds.swiftSolver: (s) => _directive(s, LevelDirective.swift),
  AchievementIds.cascadeCreator: (s) => _directive(s, LevelDirective.cascade),
  AchievementIds.unaidedMind: (s) => _directive(s, LevelDirective.unaided),
  AchievementIds.absoluteIntegrity: (s) =>
      _directive(s, LevelDirective.integrity),
  AchievementIds.flawlessExecution: (s) =>
      _directive(s, LevelDirective.flawless),
  AchievementIds.fullDirective: (s) => _clamp(s.directiveCount, 5),

  // ── I · Skill ─────────────────────────────────────────────────────────────
  AchievementIds.chainReaction: (s) => _flag(s, AchievementFlag.chainReaction),
  AchievementIds.untouchable: (s) => _flag(s, AchievementFlag.untouchable),
  AchievementIds.perfectTen: (s) => _clamp(s.bestJamFreeRun, 10),
  AchievementIds.masterPlanner: (s) => _flag(s, AchievementFlag.masterPlanner),

  // ── J · Daily Challenge ───────────────────────────────────────────────────
  AchievementIds.dailyDabbler: (s) => s.dailyCompleted >= 1 ? 1 : 0,
  AchievementIds.dailyRegular: (s) => _clamp(s.dailyCompleted, 10),
  AchievementIds.dailyDevotee: (s) => _clamp(s.dailyCompleted, 50),
  AchievementIds.dailyArchivist: (s) => _clamp(s.dailyArchived, 10),
  AchievementIds.calendarCloser: (s) =>
      _flag(s, AchievementFlag.calendarCloser),

  // ── K · Streaks ───────────────────────────────────────────────────────────
  AchievementIds.backAgain: (s) => _clamp(s.bestPlayStreakDays, 3),
  AchievementIds.weeklyWarrior: (s) => _clamp(s.bestPlayStreakDays, 7),
  AchievementIds.dedicated: (s) => _clamp(s.bestPlayStreakDays, 30),
  AchievementIds.unbreakable: (s) => _clamp(s.bestPlayStreakDays, 100),

  // ── L · Exploration ───────────────────────────────────────────────────────
  AchievementIds.fullSpectrum: (s) => _clamp(s.silhouetteFamilyCount, 4),
};

/// One achievement's evaluated state.
final class AchievementProgress {
  const AchievementProgress({
    required this.def,
    required this.current,
    required this.unlocked,
  });

  final AchievementDef def;

  /// Local progress, clamped to [AchievementDef.target].
  final int current;

  /// True once [current] reaches the target — or once the unlock was recorded,
  /// which is what keeps a badge earned after, say, a streak breaks.
  final bool unlocked;

  int get target => def.target;

  double get fraction => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);
}

/// Evaluates the whole catalog against [stats].
///
/// [alreadyUnlocked] is the persisted unlock ledger; entries in it stay
/// unlocked even if their underlying counter would no longer satisfy the rule.
List<AchievementProgress> evaluateAll(
  AchievementStats stats, {
  Set<String> alreadyUnlocked = const {},
}) {
  return <AchievementProgress>[
    for (final def in kAchievementCatalog)
      () {
        final fn = kAchievementRules[def.id];
        final current = fn == null ? 0 : _clamp(fn(stats), def.target);
        return AchievementProgress(
          def: def,
          current: current,
          unlocked: alreadyUnlocked.contains(def.id) || current >= def.target,
        );
      }(),
  ];
}
