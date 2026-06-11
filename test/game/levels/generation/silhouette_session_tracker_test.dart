import 'package:chain_pop/game/levels/generation/silhouette_session_tracker.dart';
import 'package:chain_pop/game/levels/generation/silhouettes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('penalizes consecutive geometricLattice silhouettes', () {
    final tracker = SilhouetteSessionTracker();
    tracker.record(SilhouetteId.cross);
    tracker.record(SilhouetteId.ring);

    expect(tracker.trailingGeometricStreak(), 2);
    expect(
      tracker.streakPenalty(SilhouetteId.diamond),
      lessThan(0),
    );
    expect(
      tracker.diversityBoost(SilhouetteId.organicBlob),
      greaterThan(0),
    );
  });
}
