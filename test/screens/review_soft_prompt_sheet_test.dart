import 'dart:io';

import 'package:chain_pop/screens/widgets/review_soft_prompt_sheet.dart';
import 'package:chain_pop/services/analytics/no_op_analytics_service.dart';
import 'package:chain_pop/services/review/review_coordinator.dart';
import 'package:chain_pop/services/storage/hive_chain_pop_persistence.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:in_app_review/in_app_review.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HiveChainPopPersistence persistence;
  late NoOpAnalyticsService analytics;
  late ReviewCoordinator coordinator;

  setUpAll(() async {
    final tempDir = await Directory.systemTemp.createTemp('review_sheet_test_');
    Hive.init(tempDir.path);
    persistence = HiveChainPopPersistence();
    await persistence.open();
    StorageService.installForTesting(persistence);
  });

  setUp(() async {
    await persistence.clearProgress();
    analytics = NoOpAnalyticsService();
    coordinator = ReviewCoordinator(
      persistence: persistence,
      analytics: analytics,
      inAppReview: InAppReview.instance,
    );
  });

  tearDownAll(() async {
    StorageService.uninstallForTesting();
  });

  testWidgets('renders all copy and action buttons directly', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReviewSoftPromptSheet(
            level: 15,
            coordinator: coordinator,
          ),
        ),
      ),
    );

    expect(find.text('LEAVE A QUICK RATING'), findsOneWidget);
    expect(find.text('RATE CHAIN POP'), findsOneWidget);
    expect(find.text('REMIND ME LATER'), findsOneWidget);
    expect(find.text("DON'T ASK AGAIN"), findsOneWidget);
  });

  testWidgets('tapping Remind Me Later in sheet pops with later action',
      (tester) async {
    ReviewPromptAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedAction = await showModalBottomSheet<ReviewPromptAction>(
                  context: context,
                  builder: (ctx) => ReviewSoftPromptSheet(
                    level: 15,
                    coordinator: coordinator,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('REMIND ME LATER'));
    await tester.pumpAndSettle();

    expect(selectedAction, ReviewPromptAction.later);
  });

  testWidgets('tapping Dont Ask Again in sheet pops with never action',
      (tester) async {
    ReviewPromptAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedAction = await showModalBottomSheet<ReviewPromptAction>(
                  context: context,
                  builder: (ctx) => ReviewSoftPromptSheet(
                    level: 15,
                    coordinator: coordinator,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("DON'T ASK AGAIN"));
    await tester.pumpAndSettle();

    expect(selectedAction, ReviewPromptAction.never);
  });

  testWidgets('tapping Rate Chain Pop in sheet pops with rate action',
      (tester) async {
    ReviewPromptAction? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selectedAction = await showModalBottomSheet<ReviewPromptAction>(
                  context: context,
                  builder: (ctx) => ReviewSoftPromptSheet(
                    level: 15,
                    coordinator: coordinator,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RATE CHAIN POP'));
    await tester.pumpAndSettle();

    expect(selectedAction, ReviewPromptAction.rate);
  });
}
