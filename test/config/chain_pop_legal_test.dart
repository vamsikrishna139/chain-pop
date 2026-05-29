import 'package:chain_pop/config/chain_pop_legal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default privacy policy URL points at Unbound hosted policy',
    () {
      expect(
        ChainPopLegal.privacyPolicyUrl,
        'https://sites.google.com/view/unbound-policy/home',
      );
    },
  );
}
