/// The frozen Play Games achievement catalog.
///
/// Forty-eight entries totalling exactly 2,000 points — Google's hard cap for a
/// single game. Every value is a multiple of 5 and none exceeds 200, and every
/// incremental step count stays inside the documented 2–10,000 range.
/// `achievement_catalog_test.dart` asserts all four properties, so the budget
/// cannot drift without a test failing.
///
/// **Publishing is irreversible.** Once an achievement is live in Play Console
/// it cannot be unpublished, so treat [kAchievementCatalog] as append-mostly:
/// prices and ids here must match what was published, and a removal is not a
/// removal — it is a permanently orphaned entry on Google's side.
///
/// Pricing follows one rule: **points track first reachability.** An entry that
/// only becomes possible in sector 6 costs more than one available on level 1,
/// which is what keeps the ladder defensible under quality checklist item 2.11.
library;

/// How Play Games models the entry.
///
/// [standard] is a single `unlock()` call. [incremental] reports absolute
/// progress via `setSteps()` and renders a progress bar in the Play Games UI.
///
/// A target of 1 *must* be [standard] — Google's minimum step count is 2.
enum AchievementKind { standard, incremental }

/// Catalog section. Used to group the local achievements screen and to assert
/// per-section point subtotals in tests.
enum AchievementTrack {
  firstHour,
  depth,
  allTracks,
  stars,
  volume,
  mechanics,
  guardians,
  directives,
  skill,
  daily,
  streaks,
  exploration,
}

extension AchievementTrackLabel on AchievementTrack {
  String get label => switch (this) {
        AchievementTrack.firstHour => 'First hour',
        AchievementTrack.depth => 'Depth',
        AchievementTrack.allTracks => 'All three tracks',
        AchievementTrack.stars => 'Stars',
        AchievementTrack.volume => 'Volume',
        AchievementTrack.mechanics => 'Mechanics',
        AchievementTrack.guardians => 'Guardians',
        AchievementTrack.directives => 'Directives',
        AchievementTrack.skill => 'Skill',
        AchievementTrack.daily => 'Daily Challenge',
        AchievementTrack.streaks => 'Streaks',
        AchievementTrack.exploration => 'Exploration',
      };
}

/// One catalog entry.
///
/// [id] is our stable internal key — it is what the Hive unlock ledger records
/// and it never changes. [playGamesId] is the opaque string Play Console mints
/// when the achievement is created there; it stays null until the catalog is
/// published, and the sink skips any entry that has not been mapped yet.
final class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.name,
    required this.description,
    required this.points,
    required this.kind,
    required this.track,
    this.steps,
    this.scale = 1,
    this.hidden = false,
    this.playGamesId,
  });

  final String id;
  final String name;
  final String description;
  final int points;
  final AchievementKind kind;
  final AchievementTrack track;

  /// Step count reported to Play Games. Null for [AchievementKind.standard].
  final int? steps;

  /// Local units per reported step.
  ///
  /// Google caps steps at 10,000, so the large volume tiers report a divided
  /// value: Node Lord tracks 50,000 nodes as 5,000 steps of 10. The sink calls
  /// `setSteps(local ~/ scale)`.
  final int scale;

  final bool hidden;

  /// Play Console's generated id. Null until published — see [playGamesIds].
  final String? playGamesId;

  /// Local progress value at which this unlocks.
  ///
  /// Standard entries complete at 1; incremental entries at `steps * scale`.
  int get target => switch (kind) {
        AchievementKind.standard => 1,
        AchievementKind.incremental => (steps ?? 1) * scale,
      };

  /// Absolute step value to report for [localProgress], clamped to [steps].
  int stepsFor(int localProgress) {
    final s = steps;
    if (s == null) return 0;
    final scaled = localProgress ~/ scale;
    return scaled < 0 ? 0 : (scaled > s ? s : scaled);
  }
}

/// Stable internal ids.
///
/// Referenced by [kAchievementCatalog] and by the rule engine, so a typo is a
/// compile error rather than a silently dead rule.
abstract final class AchievementIds {
  AchievementIds._();

  // A · First hour
  static const coldStart = 'cold_start';
  static const findingFooting = 'finding_footing';
  static const hundredDown = 'hundred_down';
  static const firstGuardian = 'first_guardian';

  // B · Depth
  static const journeyBegun = 'journey_begun';
  static const century = 'century';
  static const deepRun = 'deep_run';
  static const halfwayHome = 'halfway_home';
  static const finalApproach = 'final_approach';
  static const guardian40 = 'guardian_40';

  // C · All three tracks
  static const threeFronts = 'three_fronts';
  static const tripleThreat = 'triple_threat';

  // D · Stars
  static const risingStar = 'rising_star';
  static const starCollector = 'star_collector';
  static const constellation = 'constellation';
  static const galaxy = 'galaxy';

  // E · Volume
  static const nodeRunner = 'node_runner';
  static const nodeKnight = 'node_knight';
  static const nodeLord = 'node_lord';
  static const nodeLegend = 'node_legend';

  // F · Mechanics
  static const coreCollector = 'core_collector';
  static const locksmith = 'locksmith';
  static const relayRunner = 'relay_runner';
  static const phaseShift = 'phase_shift';
  static const portalHopper = 'portal_hopper';

  // G · Guardians
  static const guardianHunter = 'guardian_hunter';
  static const guardianPerfect = 'guardian_perfect';
  static const sectorClean = 'sector_clean';

  // H · Directives
  static const swiftSolver = 'swift_solver';
  static const cascadeCreator = 'cascade_creator';
  static const unaidedMind = 'unaided_mind';
  static const absoluteIntegrity = 'absolute_integrity';
  static const flawlessExecution = 'flawless_execution';
  static const fullDirective = 'full_directive';

  // I · Skill
  static const chainReaction = 'chain_reaction';
  static const untouchable = 'untouchable';
  static const perfectTen = 'perfect_ten';
  static const masterPlanner = 'master_planner';

  // J · Daily Challenge
  static const dailyDabbler = 'daily_dabbler';
  static const dailyRegular = 'daily_regular';
  static const dailyDevotee = 'daily_devotee';
  static const dailyArchivist = 'daily_archivist';
  static const calendarCloser = 'calendar_closer';

  // K · Streaks
  static const backAgain = 'back_again';
  static const weeklyWarrior = 'weekly_warrior';
  static const dedicated = 'dedicated';
  static const unbreakable = 'unbreakable';

  // L · Exploration
  static const fullSpectrum = 'full_spectrum';
}

/// Play Console's generated ids, keyed by [AchievementDef.id].
///
/// Populate from `android/app/src/main/res/values/games-ids.xml` after creating
/// the catalog in Play Console. Entries absent from this map are tracked
/// locally but never synced — which is the correct behaviour pre-publish, and
/// is what lets the whole system ship and be played against before any Google
/// setup exists.
const Map<String, String> playGamesIds = <String, String>{
  AchievementIds.coldStart: 'CgkI5dq9r9oDEAIQFA',
  AchievementIds.findingFooting: 'CgkI5dq9r9oDEAIQLQ',
  AchievementIds.hundredDown: 'CgkI5dq9r9oDEAIQKw',
  AchievementIds.firstGuardian: 'CgkI5dq9r9oDEAIQJw',
  AchievementIds.journeyBegun: 'CgkI5dq9r9oDEAIQGw',
  AchievementIds.century: 'CgkI5dq9r9oDEAIQHw',
  AchievementIds.deepRun: 'CgkI5dq9r9oDEAIQJA',
  AchievementIds.halfwayHome: 'CgkI5dq9r9oDEAIQAw',
  AchievementIds.finalApproach: 'CgkI5dq9r9oDEAIQKQ',
  AchievementIds.guardian40: 'CgkI5dq9r9oDEAIQGQ',
  AchievementIds.threeFronts: 'CgkI5dq9r9oDEAIQGg',
  AchievementIds.tripleThreat: 'CgkI5dq9r9oDEAIQFw',
  AchievementIds.risingStar: 'CgkI5dq9r9oDEAIQKA',
  AchievementIds.starCollector: 'CgkI5dq9r9oDEAIQIQ',
  AchievementIds.constellation: 'CgkI5dq9r9oDEAIQFg',
  AchievementIds.galaxy: 'CgkI5dq9r9oDEAIQAA',
  AchievementIds.nodeRunner: 'CgkI5dq9r9oDEAIQLg',
  AchievementIds.nodeKnight: 'CgkI5dq9r9oDEAIQJQ',
  AchievementIds.nodeLord: 'CgkI5dq9r9oDEAIQLw',
  AchievementIds.nodeLegend: 'CgkI5dq9r9oDEAIQHg',
  AchievementIds.coreCollector: 'CgkI5dq9r9oDEAIQGA',
  AchievementIds.locksmith: 'CgkI5dq9r9oDEAIQAQ',
  AchievementIds.relayRunner: 'CgkI5dq9r9oDEAIQDA',
  AchievementIds.phaseShift: 'CgkI5dq9r9oDEAIQBQ',
  AchievementIds.portalHopper: 'CgkI5dq9r9oDEAIQEw',
  AchievementIds.guardianHunter: 'CgkI5dq9r9oDEAIQBg',
  AchievementIds.guardianPerfect: 'CgkI5dq9r9oDEAIQDQ',
  AchievementIds.sectorClean: 'CgkI5dq9r9oDEAIQIg',
  AchievementIds.swiftSolver: 'CgkI5dq9r9oDEAIQCw',
  AchievementIds.cascadeCreator: 'CgkI5dq9r9oDEAIQBw',
  AchievementIds.unaidedMind: 'CgkI5dq9r9oDEAIQIw',
  AchievementIds.absoluteIntegrity: 'CgkI5dq9r9oDEAIQAg',
  AchievementIds.flawlessExecution: 'CgkI5dq9r9oDEAIQKg',
  AchievementIds.fullDirective: 'CgkI5dq9r9oDEAIQCA',
  AchievementIds.chainReaction: 'CgkI5dq9r9oDEAIQDg',
  AchievementIds.untouchable: 'CgkI5dq9r9oDEAIQJg',
  AchievementIds.perfectTen: 'CgkI5dq9r9oDEAIQEQ',
  AchievementIds.masterPlanner: 'CgkI5dq9r9oDEAIQLA',
  AchievementIds.dailyDabbler: 'CgkI5dq9r9oDEAIQEg',
  AchievementIds.dailyRegular: 'CgkI5dq9r9oDEAIQCQ',
  AchievementIds.dailyDevotee: 'CgkI5dq9r9oDEAIQCg',
  AchievementIds.dailyArchivist: 'CgkI5dq9r9oDEAIQDw',
  AchievementIds.calendarCloser: 'CgkI5dq9r9oDEAIQHA',
  AchievementIds.backAgain: 'CgkI5dq9r9oDEAIQIA',
  AchievementIds.weeklyWarrior: 'CgkI5dq9r9oDEAIQFQ',
  AchievementIds.dedicated: 'CgkI5dq9r9oDEAIQEA',
  AchievementIds.unbreakable: 'CgkI5dq9r9oDEAIQHQ',
  AchievementIds.fullSpectrum: 'CgkI5dq9r9oDEAIQBA',
};

/// The catalog. Order is display order.
const List<AchievementDef> kAchievementCatalog = <AchievementDef>[
  // ── A · First hour ────────────────────────────────────────────────────────
  // Exactly one of these can fire inside the first five minutes (checklist
  // 2.13); the rest are spaced by construction.
  AchievementDef(
    id: AchievementIds.coldStart,
    name: 'Cold Start',
    description: 'Clear level 1.',
    points: 5,
    kind: AchievementKind.standard,
    track: AchievementTrack.firstHour,
  ),
  AchievementDef(
    id: AchievementIds.findingFooting,
    name: 'Finding Footing',
    description: 'Reach level 10.',
    points: 10,
    kind: AchievementKind.incremental,
    steps: 10,
    track: AchievementTrack.firstHour,
  ),
  AchievementDef(
    id: AchievementIds.hundredDown,
    name: 'Hundred Down',
    description: 'Clear 100 nodes.',
    points: 15,
    kind: AchievementKind.incremental,
    steps: 100,
    track: AchievementTrack.firstHour,
  ),
  AchievementDef(
    id: AchievementIds.firstGuardian,
    name: 'First Guardian',
    description: 'Clear level 25 and defeat your first Guardian.',
    points: 15,
    kind: AchievementKind.standard,
    track: AchievementTrack.firstHour,
  ),

  // ── B · Depth ─────────────────────────────────────────────────────────────
  // "Reach level N" is the frontier on the deepest of the three tracks.
  AchievementDef(
    id: AchievementIds.journeyBegun,
    name: 'Journey Begun',
    description: 'Reach level 50 on any difficulty.',
    points: 20,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.depth,
  ),
  AchievementDef(
    id: AchievementIds.century,
    name: 'Century',
    description: 'Reach level 100 on any difficulty.',
    points: 25,
    kind: AchievementKind.incremental,
    steps: 100,
    track: AchievementTrack.depth,
  ),
  AchievementDef(
    id: AchievementIds.deepRun,
    name: 'Deep Run',
    description: 'Reach level 250 on any difficulty.',
    points: 35,
    kind: AchievementKind.incremental,
    steps: 250,
    track: AchievementTrack.depth,
  ),
  AchievementDef(
    id: AchievementIds.halfwayHome,
    name: 'Halfway Home',
    description: 'Reach level 500 on any difficulty.',
    points: 50,
    kind: AchievementKind.incremental,
    steps: 500,
    track: AchievementTrack.depth,
  ),
  AchievementDef(
    id: AchievementIds.finalApproach,
    name: 'Final Approach',
    description: 'Reach level 750 on any difficulty.',
    points: 55,
    kind: AchievementKind.incremental,
    steps: 750,
    track: AchievementTrack.depth,
  ),
  AchievementDef(
    id: AchievementIds.guardian40,
    name: 'Guardian 40',
    description: 'Clear level 1,000 — the last of the authored worlds.',
    points: 120,
    kind: AchievementKind.incremental,
    steps: 1000,
    track: AchievementTrack.depth,
  ),

  // ── C · All three tracks ──────────────────────────────────────────────────
  // Easy, Medium and Hard are independent progressions with separate star
  // records. These are the only entries that require touching more than one.
  AchievementDef(
    id: AchievementIds.threeFronts,
    name: 'Three Fronts',
    description: 'Reach level 50 on Easy, Medium and Hard.',
    points: 40,
    kind: AchievementKind.incremental,
    steps: 3,
    track: AchievementTrack.allTracks,
  ),
  AchievementDef(
    id: AchievementIds.tripleThreat,
    name: 'Triple Threat',
    description: 'Reach level 200 on Easy, Medium and Hard.',
    points: 70,
    kind: AchievementKind.incremental,
    steps: 3,
    track: AchievementTrack.allTracks,
  ),

  // ── D · Stars ─────────────────────────────────────────────────────────────
  AchievementDef(
    id: AchievementIds.risingStar,
    name: 'Rising Star',
    description: 'Earn 100 stars across all difficulties.',
    points: 20,
    kind: AchievementKind.incremental,
    steps: 100,
    track: AchievementTrack.stars,
  ),
  AchievementDef(
    id: AchievementIds.starCollector,
    name: 'Star Collector',
    description: 'Earn 500 stars across all difficulties.',
    points: 35,
    kind: AchievementKind.incremental,
    steps: 500,
    track: AchievementTrack.stars,
  ),
  AchievementDef(
    id: AchievementIds.constellation,
    name: 'Constellation',
    description: 'Earn 1,500 stars across all difficulties.',
    points: 60,
    kind: AchievementKind.incremental,
    steps: 1500,
    track: AchievementTrack.stars,
  ),
  AchievementDef(
    id: AchievementIds.galaxy,
    name: 'Galaxy',
    description: 'Earn 3,000 stars across all difficulties.',
    points: 90,
    kind: AchievementKind.incremental,
    steps: 3000,
    track: AchievementTrack.stars,
  ),

  // ── E · Volume ────────────────────────────────────────────────────────────
  // The top two tiers exceed Google's 10,000-step ceiling, so they report a
  // divided value — see [AchievementDef.scale].
  AchievementDef(
    id: AchievementIds.nodeRunner,
    name: 'Node Runner',
    description: 'Clear 1,000 nodes.',
    points: 15,
    kind: AchievementKind.incremental,
    steps: 1000,
    track: AchievementTrack.volume,
  ),
  AchievementDef(
    id: AchievementIds.nodeKnight,
    name: 'Node Knight',
    description: 'Clear 10,000 nodes.',
    points: 25,
    kind: AchievementKind.incremental,
    steps: 10000,
    track: AchievementTrack.volume,
  ),
  AchievementDef(
    id: AchievementIds.nodeLord,
    name: 'Node Lord',
    description: 'Clear 50,000 nodes.',
    points: 40,
    kind: AchievementKind.incremental,
    steps: 5000,
    scale: 10,
    track: AchievementTrack.volume,
  ),
  AchievementDef(
    id: AchievementIds.nodeLegend,
    name: 'Node Legend',
    description: 'Clear 150,000 nodes.',
    points: 60,
    kind: AchievementKind.incremental,
    steps: 10000,
    scale: 15,
    track: AchievementTrack.volume,
  ),

  // ── F · Mechanics ─────────────────────────────────────────────────────────
  // Priced by the sector each mechanic first appears in (progression_profile):
  // cores S1(Hard)/S2(Medium), locks S2, relays S3, phase gates S5, portals S6.
  AchievementDef(
    id: AchievementIds.coreCollector,
    name: 'Core Collector',
    description: 'Extract 100 cores.',
    points: 25,
    kind: AchievementKind.incremental,
    steps: 100,
    track: AchievementTrack.mechanics,
  ),
  AchievementDef(
    id: AchievementIds.locksmith,
    name: 'Locksmith',
    description: 'Open 50 locked nodes.',
    points: 25,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.mechanics,
  ),
  AchievementDef(
    id: AchievementIds.relayRunner,
    name: 'Relay Runner',
    description: 'Clear 50 relays.',
    points: 30,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.mechanics,
  ),
  AchievementDef(
    id: AchievementIds.phaseShift,
    name: 'Phase Shift',
    description: 'Clear 50 phase gates.',
    points: 40,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.mechanics,
  ),
  AchievementDef(
    id: AchievementIds.portalHopper,
    name: 'Portal Hopper',
    description: 'Traverse 50 portal pairs.',
    points: 45,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.mechanics,
  ),

  // ── G · Guardians ─────────────────────────────────────────────────────────
  AchievementDef(
    id: AchievementIds.guardianHunter,
    name: 'Guardian Hunter',
    description: 'Clear 10 Guardian levels.',
    points: 30,
    kind: AchievementKind.incremental,
    steps: 10,
    track: AchievementTrack.guardians,
  ),
  AchievementDef(
    id: AchievementIds.guardianPerfect,
    name: 'Guardian Perfect',
    description: 'Earn 3 stars on a Guardian level.',
    points: 35,
    kind: AchievementKind.standard,
    track: AchievementTrack.guardians,
  ),
  AchievementDef(
    id: AchievementIds.sectorClean,
    name: 'Sector Clean',
    description: 'Earn 3 stars on all five Guardians in a single sector.',
    points: 55,
    kind: AchievementKind.incremental,
    steps: 5,
    track: AchievementTrack.guardians,
  ),

  // ── H · Directives ────────────────────────────────────────────────────────
  // Priced by the sector each directive first enters the pool (level_directive):
  // SWIFT S1, CASCADE S1 (Hard only — Easy has no cores), UNAIDED S2,
  // INTEGRITY S5, FLAWLESS S6.
  AchievementDef(
    id: AchievementIds.swiftSolver,
    name: 'Swift Solver',
    description: 'Earn 3 stars on a level with the SWIFT directive.',
    points: 15,
    kind: AchievementKind.standard,
    track: AchievementTrack.directives,
  ),
  AchievementDef(
    id: AchievementIds.cascadeCreator,
    name: 'Cascade Creator',
    description: 'Earn 3 stars on a level with the CASCADE directive.',
    points: 25,
    kind: AchievementKind.standard,
    track: AchievementTrack.directives,
  ),
  AchievementDef(
    id: AchievementIds.unaidedMind,
    name: 'Unaided Mind',
    description: 'Earn 3 stars on a level with the UNAIDED directive.',
    points: 25,
    kind: AchievementKind.standard,
    track: AchievementTrack.directives,
  ),
  AchievementDef(
    id: AchievementIds.absoluteIntegrity,
    name: 'Absolute Integrity',
    description: 'Earn 3 stars on a level with the INTEGRITY directive.',
    points: 40,
    kind: AchievementKind.standard,
    track: AchievementTrack.directives,
  ),
  AchievementDef(
    id: AchievementIds.flawlessExecution,
    name: 'Flawless Execution',
    description: 'Earn 3 stars on a level with the FLAWLESS directive.',
    points: 55,
    kind: AchievementKind.standard,
    track: AchievementTrack.directives,
  ),
  AchievementDef(
    id: AchievementIds.fullDirective,
    name: 'Full Directive',
    description: 'Earn 3 stars on a level of every directive.',
    points: 70,
    kind: AchievementKind.incremental,
    steps: 5,
    track: AchievementTrack.directives,
  ),

  // ── I · Skill ─────────────────────────────────────────────────────────────
  AchievementDef(
    id: AchievementIds.chainReaction,
    name: 'Chain Reaction',
    description: 'Reach a ×5 extraction combo.',
    points: 25,
    kind: AchievementKind.standard,
    hidden: true,
    track: AchievementTrack.skill,
  ),
  AchievementDef(
    id: AchievementIds.untouchable,
    name: 'Untouchable',
    description: 'Clear a Hard level at 100% network integrity.',
    points: 40,
    kind: AchievementKind.standard,
    track: AchievementTrack.skill,
  ),
  AchievementDef(
    id: AchievementIds.perfectTen,
    name: 'Perfect Ten',
    description: 'Clear 10 levels in a row without a jam.',
    points: 55,
    kind: AchievementKind.incremental,
    steps: 10,
    track: AchievementTrack.skill,
  ),
  AchievementDef(
    id: AchievementIds.masterPlanner,
    name: 'Master Planner',
    description: 'Clear a Hard level with no undo, no hint and no jam.',
    points: 65,
    kind: AchievementKind.standard,
    track: AchievementTrack.skill,
  ),

  // ── J · Daily Challenge ───────────────────────────────────────────────────
  AchievementDef(
    id: AchievementIds.dailyDabbler,
    name: 'Daily Dabbler',
    description: 'Complete your first Daily Challenge.',
    points: 15,
    kind: AchievementKind.standard,
    track: AchievementTrack.daily,
  ),
  AchievementDef(
    id: AchievementIds.dailyRegular,
    name: 'Daily Regular',
    description: 'Complete 10 Daily Challenges.',
    points: 30,
    kind: AchievementKind.incremental,
    steps: 10,
    track: AchievementTrack.daily,
  ),
  AchievementDef(
    id: AchievementIds.dailyDevotee,
    name: 'Daily Devotee',
    description: 'Complete 50 Daily Challenges.',
    points: 55,
    kind: AchievementKind.incremental,
    steps: 50,
    track: AchievementTrack.daily,
  ),
  AchievementDef(
    id: AchievementIds.dailyArchivist,
    name: 'Daily Archivist',
    description: 'Complete 10 Daily Challenges from past dates.',
    points: 45,
    kind: AchievementKind.incremental,
    steps: 10,
    track: AchievementTrack.daily,
  ),
  AchievementDef(
    id: AchievementIds.calendarCloser,
    name: 'Calendar Closer',
    description: 'Complete every day in a single calendar month.',
    points: 80,
    kind: AchievementKind.standard,
    track: AchievementTrack.daily,
  ),

  // ── K · Streaks ───────────────────────────────────────────────────────────
  // Streaks count days on which a level was *completed*, not days the app was
  // opened, and they track the best run ever rather than the current one.
  AchievementDef(
    id: AchievementIds.backAgain,
    name: 'Back Again',
    description: 'Complete a level on 3 days in a row.',
    points: 20,
    kind: AchievementKind.incremental,
    steps: 3,
    track: AchievementTrack.streaks,
  ),
  AchievementDef(
    id: AchievementIds.weeklyWarrior,
    name: 'Weekly Warrior',
    description: 'Complete a level on 7 days in a row.',
    points: 35,
    kind: AchievementKind.incremental,
    steps: 7,
    track: AchievementTrack.streaks,
  ),
  AchievementDef(
    id: AchievementIds.dedicated,
    name: 'Dedicated',
    description: 'Complete a level on 30 days in a row.',
    points: 70,
    kind: AchievementKind.incremental,
    steps: 30,
    track: AchievementTrack.streaks,
  ),
  AchievementDef(
    id: AchievementIds.unbreakable,
    name: 'Unbreakable',
    description: 'Complete a level on 100 days in a row.',
    points: 100,
    kind: AchievementKind.incremental,
    steps: 100,
    track: AchievementTrack.streaks,
  ),

  // ── L · Exploration ───────────────────────────────────────────────────────
  AchievementDef(
    id: AchievementIds.fullSpectrum,
    name: 'Full Spectrum',
    description: 'Clear a board from all four silhouette families.',
    points: 45,
    kind: AchievementKind.incremental,
    steps: 4,
    track: AchievementTrack.exploration,
  ),
];

/// Google's hard cap on total points for one game.
const int kPlayGamesPointBudget = 2000;

/// Google's per-achievement point ceiling.
const int kPlayGamesMaxPointsPerAchievement = 200;

/// Google's incremental step bounds, inclusive.
const int kPlayGamesMinSteps = 2;
const int kPlayGamesMaxSteps = 10000;

/// Catalog lookup by [AchievementDef.id].
final Map<String, AchievementDef> kAchievementsById = <String, AchievementDef>{
  for (final a in kAchievementCatalog) a.id: a,
};

/// Sum of every entry's points. Asserted to equal [kPlayGamesPointBudget].
int get kAchievementTotalPoints =>
    kAchievementCatalog.fold(0, (sum, a) => sum + a.points);
