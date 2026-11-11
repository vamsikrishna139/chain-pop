import 'package:chain_pop/screens/game/widgets/privacy_rights_sheet.dart';
import 'package:chain_pop/services/privacy/data_deletion_service.dart';
import 'package:chain_pop/services/privacy/privacy_request_email.dart';
import 'package:chain_pop/services/privacy/support_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _EmailCall {
  _EmailCall(this.type, this.ids);
  final PrivacyRequestType type;
  final SupportIds? ids;
}

void main() {
  late List<_EmailCall> emails;
  late int deletions;
  late int deletedCallbacks;
  late String analyticsId;

  setUp(() {
    emails = [];
    deletions = 0;
    deletedCallbacks = 0;
    analyticsId = 'abcdef0123456789';
  });

  SupportIdentity identity() => SupportIdentity(
        analyticsId: () async => analyticsId,
        purchaseId: () async => r'$RCAnonymousID:p1',
      );

  Future<void> pump(WidgetTester tester, {bool allowDelete = true}) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final id = identity();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PrivacyRightsContent(
          accent: Colors.cyan,
          showAdChoicesButton: false,
          identity: id,
          onDataDeleted: allowDelete ? () => deletedCallbacks++ : null,
          deletionService: DataDeletionService(
            identity: id,
            resetAnalytics: () async => analyticsId = 'ffff000011112222',
            deleteUnsentCrashReports: () async {},
            clearLocalProgress: () async => deletions++,
          ),
          emailLauncher: (_, type, ids) async => emails.add(_EmailCall(type, ids)),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the short Support ID and copies the full one',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester);
    expect(find.text('Your Support ID'), findsOneWidget);
    expect(find.text('ABCD-EF01'), findsOneWidget);

    await tester.tap(find.byTooltip('Copy Support ID'));
    await tester.pump();
    expect(copied, 'abcdef0123456789');
  });

  testWidgets('no analytics id → "None", no copy button',
      (tester) async {
    analyticsId = '';
    await pump(tester);
    expect(find.text('None (no analytics ID on this device)'), findsOneWidget);
    expect(find.byTooltip('Copy Support ID'), findsNothing);
  });

  testWidgets('request buttons open the email with the right type',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Request a copy of my data'));
    await tester.tap(find.text('Other request'));
    await tester.pump();
    expect(emails.map((e) => e.type),
        [PrivacyRequestType.access, PrivacyRequestType.other]);
  });

  testWidgets('cancel does not delete', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Delete my data'));
    await tester.pumpAndSettle();
    expect(find.text('Delete data on this device?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletions, 0);
    expect(deletedCallbacks, 0);
  });

  testWidgets('confirm deletes once and the request carries the OLD id',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Delete my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(deletions, 1);
    expect(deletedCallbacks, 1);
    expect(find.text('Send deletion request'), findsOneWidget);
    // Sheet now shows the new (reset) id.
    expect(find.text('FFFF-0000'), findsOneWidget);

    await tester.tap(find.text('Send deletion request'));
    await tester.pumpAndSettle();
    expect(emails, hasLength(1));
    expect(emails.single.type, PrivacyRequestType.delete);
    expect(emails.single.ids?.analyticsId, 'abcdef0123456789');
  });

  testWidgets('without onDataDeleted (in-game) there is no delete button',
      (tester) async {
    await pump(tester, allowDelete: false);
    expect(find.text('Delete my data'), findsNothing);
    expect(find.textContaining('available from Settings on the home screen'),
        findsOneWidget);
  });
}
