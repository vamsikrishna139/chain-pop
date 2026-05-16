import 'chain_pop_persistence.dart';

/// Service location for persisted gameplay state ([AdsLocator]-style singleton).
abstract final class StorageLocator {
  StorageLocator._();

  static ChainPopPersistence? _instance;

  static ChainPopPersistence get instance =>
      _instance ?? (throw StateError('StorageLocator not installed — call StorageService.init()'));

  static void install(ChainPopPersistence persistence) {
    _instance = persistence;
  }

  /// Clears the holder (tests that re-bootstrap storage may call this sparingly).
  static void uninstall() => _instance = null;
}
