import 'chain_pop_persistence.dart';

/// Application-facing storage contract for persisted gameplay state.
///
/// Same surface as [ChainPopPersistence]; implementations include
/// [HiveChainPopPersistence]. The active instance is held on [StorageLocator]
/// and exposed via [StorageService] static helpers.
abstract interface class ChainPopStorage implements ChainPopPersistence {}
