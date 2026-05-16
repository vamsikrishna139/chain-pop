import 'package:chain_pop/config/chain_pop_legal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default privacy policy URL points at hosted gist',
    () {
      expect(
        ChainPopLegal.privacyPolicyUrl,
        'https://gist.github.com/vamsikrishna139/426c736eb50f35cb125b37f64259f925',
      );
    },
  );
}
