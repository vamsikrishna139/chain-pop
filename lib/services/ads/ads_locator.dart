import 'ad_service.dart';
import 'no_op_ad_service.dart';

/// Minimal service location — [install] from [main], tests keep default [NoOpAdService].
abstract final class AdsLocator {
  AdsLocator._();

  static AdService _instance = NoOpAdService();

  static AdService get instance => _instance;

  static void install(AdService service) {
    _instance = service;
  }
}
