import 'dart:io';

import 'package:chain_pop/game/levels/generation/difficulty_mode.dart';
import 'package:chain_pop/game/levels/level_manager.dart';
import 'package:chain_pop/services/analytics/analytics_consent.dart';
import 'package:chain_pop/services/privacy/data_deletion_service.dart';
import 'package:chain_pop/services/privacy/support_identity.dart';
import 'package:chain_pop/services/storage/storage_locator.dart';
import 'package:chain_pop/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('order and receipt (fakes)', () {
    test('ids are captured before the analytics reset, steps run in order',
        () async {
      final log = <String>[];
      var currentId = 'old-analytics-id';
      final service = DataDeletionService(
        identity: SupportIdentity(
          analyticsId: () async {
            log.add('read');
            return currentId;
          },
          purchaseId: () async => r'$RCAnonymousID:p1',
        ),
        resetAnalytics: () async {
          log.add('resetAnalytics');
          currentId = 'new-analytics-id';
        },
        deleteUnsentCrashReports: () async => log.add('crash'),
        clearLocalProgress: () async => log.add('local'),
      );

      final receipt = await service.deleteMyData();

      expect(log, ['read', 'resetAnalytics', 'crash', 'local']);
      expect(receipt.previousIds.analyticsId, 'old-analytics-id');
      expect(receipt.previousIds.purchaseId, r'$RCAnonymousID:p1');
      expect(receipt.analyticsReset, isTrue);
      expect(receipt.crashReportsCleared, isTrue);
      expect(receipt.localDataCleared, isTrue);
    });

    test('Firebase failures do not stop the local wipe', () async {
      var localCleared = false;
      final service = DataDeletionService(
        identity: SupportIdentity(
          analyticsId: () async => null,
          purchaseId: () async => null,
        ),
        resetAnalytics: () async => throw StateError('no Firebase'),
        deleteUnsentCrashReports: () async => throw StateError('no Firebase'),
        clearLocalProgress: () async => localCleared = true,
      );

      final receipt = await service.deleteMyData();

      expect(localCleared, isTrue);
      expect(receipt.analyticsReset, isFalse);
      expect(receipt.crashReportsCleared, isFalse);
      expect(receipt.previousIds.analyticsId, isNull);
    });
  });

  group('real local wipe (Hive)', () {
    setUpAll(() async {
      final dir = await Directory.systemTemp.createTemp('chain_pop_delete_');
      Hive.init(dir.path);
      await StorageService.init();
      await AnalyticsConsent.load();
    });

    test(
        'progress is wiped; analytics opt-out and ad-free entitlement survive',
        () async {
      await StorageService.saveStars(DifficultyMode.easy, 3, 3);
      await StorageLocator.instance.setCachedPremium(true);
      await AnalyticsConsent.setUserEnabled(false);
      expect(StorageService.stars(DifficultyMode.easy, 3), 3);

      final service = DataDeletionService(
        identity: SupportIdentity(
          analyticsId: () async => 'id',
          purchaseId: () async => null,
        ),
        resetAnalytics: () async {},
        deleteUnsentCrashReports: () async {},
        // default clearLocalProgress → the real shared helper
      );
      await service.deleteMyData();

      expect(StorageService.stars(DifficultyMode.easy, 3), 0);
      expect(StorageLocator.instance.cachedPremium, isTrue);
      expect(LevelManager.generator.diversityLedger.window, isEmpty);
      // Re-read from disk: the opt-out must not be reset to the default (on).
      await AnalyticsConsent.load();
      expect(AnalyticsConsent.userEnabled, isFalse);

      await AnalyticsConsent.setUserEnabled(true);
      await StorageLocator.instance.setCachedPremium(false);
    });
  });
}
