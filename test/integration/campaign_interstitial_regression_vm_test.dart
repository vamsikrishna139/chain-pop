// Runs full campaign interstitial regression without a desktop embedder/Xcode.
//
//    flutter test test/integration/campaign_interstitial_regression_vm_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'campaign_interstitial_regression_suite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  registerCampaignInterstitialRegressionTests();
}
