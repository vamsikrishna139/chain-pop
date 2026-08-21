import 'difficulty_mode.dart';
import '../../world_registry.dart';

enum CampaignMechanic { phaseGate, multiRelay, portalPair }

/// Clamp mechanics behind Phase feature flags until they are ready.
const Set<CampaignMechanic> _kEnabledMechanics = {
  CampaignMechanic.phaseGate,
  CampaignMechanic.multiRelay,
  CampaignMechanic.portalPair
};

class MechanicBudget {
  final int coreCount;
  final int lockCount;
  final int relayCount;
  final int phaseGateCount;
  final int portalPairCount;

  const MechanicBudget({
    this.coreCount = 0,
    this.lockCount = 0,
    this.relayCount = 0,
    this.phaseGateCount = 0,
    this.portalPairCount = 0,
  });

  MechanicBudget copyWith({
    int? coreCount,
    int? lockCount,
    int? relayCount,
    int? phaseGateCount,
    int? portalPairCount,
  }) {
    return MechanicBudget(
      coreCount: coreCount ?? this.coreCount,
      lockCount: lockCount ?? this.lockCount,
      relayCount: relayCount ?? this.relayCount,
      phaseGateCount: phaseGateCount ?? this.phaseGateCount,
      portalPairCount: portalPairCount ?? this.portalPairCount,
    );
  }
}

class MechanicBudgetOverride {
  final int? coreCount;
  final int? lockCount;
  final int? relayCount;
  final int? phaseGateCount;
  final int? portalPairCount;

  const MechanicBudgetOverride({
    this.coreCount,
    this.lockCount,
    this.relayCount,
    this.phaseGateCount,
    this.portalPairCount,
  });

  MechanicBudget applyTo(MechanicBudget base) {
    return base.copyWith(
      coreCount: coreCount,
      lockCount: lockCount,
      relayCount: relayCount,
      phaseGateCount: phaseGateCount,
      portalPairCount: portalPairCount,
    );
  }
}

MechanicBudget budgetForLevel({
  required int levelId,
  required DifficultyMode mode,
  MechanicBudgetOverride? mechanicOverride,
}) {
  final base = budgetFor(levelId: levelId, mode: mode);
  return mechanicOverride?.applyTo(base) ?? base;
}

MechanicBudget budgetFor({required int levelId, required DifficultyMode mode}) {
  final sector =
      levelId > 10000 ? 8 : worldForLevel(levelId).sector.mechanicBudgetTier;

  int clampPhase(int count) =>
      _kEnabledMechanics.contains(CampaignMechanic.phaseGate) ? count : 0;
  int clampRelay(int count) =>
      count > 1 && !_kEnabledMechanics.contains(CampaignMechanic.multiRelay)
          ? 1
          : count;
  int clampPortal(int count) =>
      _kEnabledMechanics.contains(CampaignMechanic.portalPair) ? count : 0;

  // Easy ships **no cores**, and T1.4 — which would have given sector 3+ a
  // single core to teach the core-win before the player meets Medium — was
  // measured and dropped rather than written. Recorded here because the next
  // reader of the plan will otherwise think it was forgotten.
  //
  // Easy boards are 8-14 nodes with almost no prerequisite structure, so the
  // best `coreTapDepth` any spread-legal selection can reach on them is:
  //
  //     1 core : p50 3 taps, max 7   (measured over kReportSampleIds, sector 3+)
  //     2 cores: p50 5 taps, max 12
  //
  // A core-win fires when the last core is extracted, so adding one core turns
  // an eleven-tap clear-all board into a ~3-tap board — the exact F1 pathology
  // P1 exists to remove, in miniature, and squarely against T1.4's own gate
  // (Easy p50 >= 9 taps, <=6-tap share 0%). No core count fixes it: the ceiling
  // is a property of the geometry, and Easy's geometry is deliberately shallow.
  //
  // Teaching the core-win on Easy therefore needs Easy boards with real depth
  // first — a generation change, not an enrichment one. Until then Easy stays a
  // clear-all mode and keeps its p50 of 11 taps.
  if (mode == DifficultyMode.easy) {
    return const MechanicBudget(coreCount: 0);
  }

  // Medium's authoritative core rule (T1.3). Stated here as one curve because
  // `coreCount: 2` used to appear at *two* sites — the explicit `sector == 3`
  // branch and the default below, which covers sectors 4+ and therefore most of
  // the campaign. Bumping one and not the other produced a nonsensical curve
  // (sector 3 → 3 cores, sector 4+ → 2), so both move together and
  // `progression_profile_test` enumerates sectors 3..8 rather than spot-checking.
  //
  //     sector 1  → 0 cores   (pure on-ramp)
  //     sector 2  → 1 core    (introduce)
  //     sector 3+ → 3 cores   (established)
  if (mode == DifficultyMode.medium) {
    if (sector == 1) return const MechanicBudget(coreCount: 0);
    if (sector == 2) return const MechanicBudget(coreCount: 1, lockCount: 1);
    if (sector == 3) {
      return const MechanicBudget(coreCount: 3, lockCount: 1, relayCount: 1);
    }
    return MechanicBudget(
      coreCount: 3,
      lockCount: 2,
      relayCount: 1,
      phaseGateCount: clampPhase(sector >= 5 ? 1 : 0),
      portalPairCount: clampPortal(sector >= 6 ? 1 : 0),
    );
  }

  // Hard / Expert timeline
  int cores = 3;
  int locks = 0;
  int relays = 0;
  int gates = 0;
  int portals = 0;

  if (sector >= 2) locks = 1;
  if (sector >= 3) relays = 1;
  if (sector >= 4) locks = 2;
  if (sector >= 5) gates = 1;
  if (sector >= 6) portals = 1;
  if (sector >= 7) relays = 2;
  if (sector >= 8) gates = 2;

  return MechanicBudget(
    coreCount: cores,
    lockCount: locks,
    relayCount: clampRelay(relays),
    phaseGateCount: clampPhase(gates),
    portalPairCount: clampPortal(portals),
  );
}
