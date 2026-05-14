// Device / desktop integration driver (requires `-d`; uses Xcode toolchain on macOS).
//
// For CI/local without an embedder, run the VM copy instead:
//   flutter test test/integration/campaign_interstitial_regression_vm_test.dart

import 'package:integration_test/integration_test.dart';

import '../test/integration/campaign_interstitial_regression_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerCampaignInterstitialRegressionTests();
}
