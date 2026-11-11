import 'package:chain_pop/services/privacy/support_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SupportIds.shortenId', () {
    test('groups the first 8 chars, upper-cased', () {
      expect(SupportIds.shortenId('a1b2c3d4e5f6a7b8c9d0'), 'A1B2-C3D4');
    });
    test('ignores non-alphanumerics', () {
      expect(SupportIds.shortenId('a1-b2_c3:d4e5'), 'A1B2-C3D4');
    });
    test('short ids are not padded', () {
      expect(SupportIds.shortenId('abc'), 'ABC');
      expect(SupportIds.shortenId('abcdef'), 'ABCD-EF');
    });
    test('null / empty → null', () {
      expect(SupportIds.shortenId(null), isNull);
      expect(SupportIds.shortenId('---'), isNull);
    });
  });

  group('SupportIdentity.read', () {
    test('returns both ids when present', () async {
      final ids = await SupportIdentity(
        analyticsId: () async => 'abcdef0123456789',
        purchaseId: () async => r'$RCAnonymousID:xyz',
      ).read();
      expect(ids.analyticsId, 'abcdef0123456789');
      expect(ids.purchaseId, r'$RCAnonymousID:xyz');
      expect(ids.shortId, 'ABCD-EF01');
    });

    test('null, blank and throwing sources become null', () async {
      final ids = await SupportIdentity(
        analyticsId: () async => '  ',
        purchaseId: () async => throw StateError('not configured'),
      ).read();
      expect(ids.analyticsId, isNull);
      expect(ids.purchaseId, isNull);
      expect(ids.shortId, isNull);
    });

    test('default sources degrade to null without Firebase/RevenueCat',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final ids = await SupportIdentity().read();
      expect(ids.analyticsId, isNull);
      expect(ids.purchaseId, isNull);
    });
  });
}
