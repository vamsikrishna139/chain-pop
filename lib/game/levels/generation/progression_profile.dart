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

  if (mode == DifficultyMode.easy) {
    return const MechanicBudget(coreCount: 0);
  }

  if (mode == DifficultyMode.medium) {
    if (sector == 1) return const MechanicBudget(coreCount: 0);
    if (sector == 2) return const MechanicBudget(coreCount: 1, lockCount: 1);
    if (sector == 3) {
      return const MechanicBudget(coreCount: 2, lockCount: 1, relayCount: 1);
    }
    return MechanicBudget(
      coreCount: 2,
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
