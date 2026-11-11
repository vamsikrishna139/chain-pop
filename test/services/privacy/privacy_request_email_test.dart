import 'package:chain_pop/config/chain_pop_legal.dart';
import 'package:chain_pop/services/privacy/privacy_request_email.dart';
import 'package:chain_pop/services/privacy/support_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ids = SupportIds(
    analyticsId: 'abc123def456',
    purchaseId: r'$RCAnonymousID:9f&x=1',
  );

  test('body carries both ids, version and platform', () {
    final body = PrivacyRequestEmail.body(
      type: PrivacyRequestType.access,
      ids: ids,
      appVersion: '1.0.0 (5)',
      platform: 'Android',
    );
    expect(body, contains('Request type: Access'));
    expect(body, contains('Support ID: abc123def456'));
    expect(body, contains(r'Purchase ID: $RCAnonymousID:9f&x=1'));
    expect(body, contains('App version: 1.0.0 (5) · Platform: Android'));
    expect(body, contains('Google Play order ID'));
  });

  test('missing ids are written as "none"', () {
    final body = PrivacyRequestEmail.body(
      type: PrivacyRequestType.delete,
      ids: SupportIds.none,
      appVersion: 'x',
      platform: 'iOS',
    );
    expect(body, contains('Request type: Delete'));
    expect(body, contains('Support ID: none'));
    expect(body, contains('Purchase ID: none'));
  });

  test('mailto uri: fixed subject, %20 spaces, escaped & and =', () {
    final uri = PrivacyRequestEmail.uri(
      type: PrivacyRequestType.other,
      ids: ids,
      appVersion: '1.0.0 (5)',
      platform: 'Android',
    );
    expect(uri.scheme, 'mailto');
    expect(uri.path, ChainPopLegal.supportEmail);
    final raw = uri.toString();
    expect(raw, isNot(contains('+')));
    expect(raw, contains('subject=Privacy%20Inquiry%20-%20Unbound'));
    // The purchase id's & and = must not split the query.
    expect(raw, contains('9f%26x%3D1'));
    final params = Uri.splitQueryString(uri.query);
    expect(params.keys, unorderedEquals(['subject', 'body']));
    expect(params['subject'], PrivacyRequestEmail.subject);
    expect(params['body'], contains(r'$RCAnonymousID:9f&x=1'));
  });
}
