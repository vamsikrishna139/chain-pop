import 'package:chain_pop/game/components/node_component.dart';
import 'package:chain_pop/game/levels/level.dart';
import 'package:chain_pop/screens/game/widgets/ad_badge.dart';
import 'package:chain_pop/screens/game/widgets/game_bottom_toolbar.dart';
import 'package:chain_pop/screens/widgets/purchases_settings_section.dart';
import 'package:chain_pop/services/subscription/subscription_locator.dart';
import 'package:chain_pop/services/subscription/subscription_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSubscription implements SubscriptionService {
  _FakeSubscription(this.restoreResult);

  final RestorePurchasesResult restoreResult;
  final _premium = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isPremium => _premium;
  @override
  Future<void> init() async {}
  @override
  Future<PurchasePremiumResult> purchasePremium() async =>
      PurchasePremiumResult.cancelled;
  @override
  Future<RestorePurchasesResult> restorePurchases() async => restoreResult;
  @override
  Future<void> refresh() async {}
  @override
  Future<String?> getPremiumPrice() async => null;
}

Widget _toolbar({required bool hintAd, required bool undoAd}) => MaterialApp(
      home: Scaffold(
        body: GameBottomToolbar(
          accent: Colors.cyan,
          showHintAdBadge: hintAd,
          showUndoAdBadge: undoAd,
          axisGuidesVisible: false,
          canUndo: true,
          onHint: () {},
          onToggleGuides: () {},
          onResetView: () {},
          onUndo: () {},
          onRestart: () {},
        ),
      ),
    );

void main() {
  group('rewarded hint survives a board rebuild', () {
    NodeComponent node() => NodeComponent(
          data: NodeData(id: 3, x: 1, y: 1, dir: Direction.up),
          cellSize: 40,
        );

    test('a highlighted node reports how far its pulse has run', () {
      final n = node();
      expect(n.highlightElapsed, isNull);
      n.highlight();
      expect(n.highlightElapsed, 0.0);
    });

    test('a rebuilt node resumes the pulse where the old one was', () {
      final rebuilt = node()..restoreHighlight(0.4);
      expect(rebuilt.isHighlighted, isTrue);
      expect(rebuilt.highlightElapsed, 0.4);
    });
  });

  group('AD badges on the toolbar', () {
    testWidgets('no badges while hint and undo are free', (tester) async {
      await tester.pumpWidget(_toolbar(hintAd: false, undoAd: false));
      expect(find.byType(AdBadge), findsNothing);
    });

    testWidgets('hint and undo each show a badge when the next tap plays an ad',
        (tester) async {
      await tester.pumpWidget(_toolbar(hintAd: true, undoAd: true));
      expect(find.byType(AdBadge), findsNWidgets(2));
    });
  });

  group('restore result is shown inside the settings sheet', () {
    tearDown(SubscriptionLocator.uninstall);

    for (final result in RestorePurchasesResult.values) {
      testWidgets('$result shows an inline message', (tester) async {
        SubscriptionLocator.install(_FakeSubscription(result));
        await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
            body: PurchasesSettingsSection(accent: Colors.cyan),
          ),
        ));
        await tester.tap(find.text('Restore purchases'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('restore-result')), findsOneWidget);
        expect(find.text(restoreResultMessage(result)), findsOneWidget);
      });
    }

    test('a failed restore no longer claims there were no purchases', () {
      expect(
        restoreResultMessage(RestorePurchasesResult.failed),
        isNot(restoreResultMessage(RestorePurchasesResult.noneFound)),
      );
    });
  });
}
