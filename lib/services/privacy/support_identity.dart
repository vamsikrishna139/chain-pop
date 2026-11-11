import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Reads a nullable identifier; a throw counts as "not available".
typedef IdSource = Future<String?> Function();

/// The identifiers a privacy request needs so we can find a player's data
/// at our providers. The app has no account, so these are the only handles.
@immutable
class SupportIds {
  const SupportIds({this.analyticsId, this.purchaseId});

  /// Firebase App Instance ID. Null when analytics-storage consent is denied
  /// or Firebase is unavailable. Turning the in-app analytics switch off does
  /// NOT clear it: the ID persists, and data collected before the opt-out is
  /// still linked to it, so it is still worth showing.
  final String? analyticsId;

  /// RevenueCat App User ID (e.g. `$RCAnonymousID:…`). Null when RevenueCat
  /// is not configured.
  final String? purchaseId;

  static const none = SupportIds();

  /// The short, player-facing form: first 8 characters of the analytics ID,
  /// upper-cased and grouped (`A1B2-C3D4`). Null when there is no analytics ID.
  String? get shortId => shortenId(analyticsId);

  static String? shortenId(String? id) {
    if (id == null) return null;
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (clean.isEmpty) return null;
    final head = clean.length > 8 ? clean.substring(0, 8) : clean;
    if (head.length <= 4) return head;
    return '${head.substring(0, 4)}-${head.substring(4)}';
  }
}

/// Reads [SupportIds] from Firebase Analytics and RevenueCat. Sources are
/// injectable so tests run without either SDK.
class SupportIdentity {
  SupportIdentity({IdSource? analyticsId, IdSource? purchaseId})
    : _analyticsId = analyticsId ?? _firebaseAppInstanceId,
      _purchaseId = purchaseId ?? _revenueCatAppUserId;

  final IdSource _analyticsId;
  final IdSource _purchaseId;

  Future<SupportIds> read() async {
    return SupportIds(
      analyticsId: await _safe(_analyticsId),
      purchaseId: await _safe(_purchaseId),
    );
  }

  static Future<String?> _safe(IdSource source) async {
    try {
      final v = await source();
      return (v == null || v.trim().isEmpty) ? null : v.trim();
    } catch (_) {
      // SDK not initialised (tests, missing config) — treat as not collected.
      return null;
    }
  }

  static Future<String?> _firebaseAppInstanceId() =>
      FirebaseAnalytics.instance.appInstanceId;

  static Future<String?> _revenueCatAppUserId() async {
    if (!await Purchases.isConfigured) return null;
    return Purchases.appUserID;
  }
}
