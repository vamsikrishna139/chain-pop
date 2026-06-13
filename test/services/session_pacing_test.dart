import 'package:chain_pop/services/session_pacing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionPacing.surgeForWinCount', () {
    test('no surge before the first interval', () {
      for (var w = 0; w < SessionPacing.surgeInterval; w++) {
        expect(SessionPacing.surgeForWinCount(w), isNull, reason: 'wins=$w');
      }
    });

    test('surge lands on every interval-th win', () {
      expect(SessionPacing.surgeForWinCount(SessionPacing.surgeInterval),
          SurgeKind.timed);
      expect(SessionPacing.surgeForWinCount(SessionPacing.surgeInterval * 2),
          SurgeKind.timed);
      expect(SessionPacing.surgeForWinCount(SessionPacing.surgeInterval * 3),
          SurgeKind.timed);
    });

    test('non-interval wins between surges are calm', () {
      expect(SessionPacing.surgeForWinCount(SessionPacing.surgeInterval + 1),
          isNull);
      expect(SessionPacing.surgeForWinCount(SessionPacing.surgeInterval * 2 - 1),
          isNull);
    });
  });

  group('SessionPacing static lifecycle', () {
    setUp(SessionPacing.reset);

    test('onWin accumulates and reset clears', () {
      expect(SessionPacing.wins, 0);
      SessionPacing.onWin();
      SessionPacing.onWin();
      expect(SessionPacing.wins, 2);
      SessionPacing.reset();
      expect(SessionPacing.wins, 0);
    });

    test('surgeForUpcomingLevel reflects the running win count', () {
      for (var i = 0; i < SessionPacing.surgeInterval; i++) {
        SessionPacing.onWin();
      }
      expect(SessionPacing.surgeForUpcomingLevel(), SurgeKind.timed);
      SessionPacing.onWin();
      expect(SessionPacing.surgeForUpcomingLevel(), isNull);
    });
  });

  group('DefaultSessionPacingController', () {
    setUp(SessionPacing.reset);

    test('delegates to the static and exposes wins', () {
      const c = defaultSessionPacingController;
      expect(c.winsThisSession, 0);
      c.onCampaignWin();
      expect(c.winsThisSession, 1);
      for (var i = 1; i < SessionPacing.surgeInterval; i++) {
        c.onCampaignWin();
      }
      expect(c.winsThisSession, SessionPacing.surgeInterval);
      expect(c.surgeForUpcomingLevel(), SurgeKind.timed);
      c.resetSession();
      expect(c.winsThisSession, 0);
    });
  });
}
