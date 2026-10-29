import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/screens/game/widgets/game_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  for (final entry in <String, Widget Function(bool premium, bool ready)>{
    'TimeUpDialog': (premium, ready) => TimeUpDialog(
          difficulty: DifficultyMode.hard,
          onRetry: () {},
          onMenu: () {},
          showRewardedContinue: true,
          rewardedAdReady: ready,
          isPremium: premium,
          onWatchAdContinue: () async {},
        ),
    'GameOverDialog': (premium, ready) => GameOverDialog(
          difficulty: DifficultyMode.hard,
          onRetry: () {},
          onMenu: () {},
          showRewardedContinue: true,
          rewardedAdReady: ready,
          isPremium: premium,
          onWatchAdContinue: () async {},
        ),
  }.entries) {
    group(entry.key, () {
      testWidgets('free users see the ad continue copy', (tester) async {
        await tester.pumpWidget(_host(entry.value(false, true)));
        expect(find.text('WATCH AD TO CONTINUE'), findsOneWidget);
      });

      testWidgets('free users see loading copy while the ad loads',
          (tester) async {
        await tester.pumpWidget(_host(entry.value(false, false)));
        expect(find.text('AD LOADING…'), findsOneWidget);
      });

      testWidgets('premium users see a plain continue with no ad copy',
          (tester) async {
        await tester.pumpWidget(_host(entry.value(true, true)));
        expect(find.text('CONTINUE'), findsOneWidget);
        expect(find.textContaining('AD'), findsNothing);
      });
    });
  }
}
