import 'chain_pop_storage.dart';

/// Service location for persisted gameplay state ([AdsLocator]-style singleton).
abstract final class StorageLocator {
  StorageLocator._();

  static ChainPopStorage? _instance;

  static ChainPopStorage get instance =>
      _instance ?? (throw StateError('StorageLocator not installed — call StorageService.init()'));

  static void install(ChainPopStorage persistence) {
    _instance = persistence;
  }

  /// Clears the holder (tests that re-bootstrap storage may call this sparingly).
  static void uninstall() => _instance = null;
}
