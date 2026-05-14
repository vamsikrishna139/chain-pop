// Device / desktop integration smoke (needs `-d`; uses real plugins).
//
//   flutter test integration_test/chain_pop_smoke_test.dart -d <deviceId> \
//       --dart-define=MOCK_ADS=true

import 'package:chain_pop/main.dart';
import 'package:integration_test/integration_test.dart';

import '../test/integration/chain_pop_navigation_smoke_suite.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  registerChainPopNavigationSmoke(beforeAll: bootstrapChainPop);
}
