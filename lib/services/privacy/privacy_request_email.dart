import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/chain_pop_legal.dart';
import 'support_identity.dart';

enum PrivacyRequestType {
  access('Access (send me a copy of my data)'),
  delete('Delete (erase my data held by your providers)'),
  other('Other');

  const PrivacyRequestType(this.label);
  final String label;
}

/// Builds the pre-filled privacy request email. Pure, so it is unit-tested.
///
/// The subject stays fixed so the inbox filter can label these mails.
abstract final class PrivacyRequestEmail {
  static const subject = 'Privacy Inquiry - Unbound';

  static String body({
    required PrivacyRequestType type,
    required SupportIds ids,
    required String appVersion,
    required String platform,
  }) {
    return 'Request type: ${type.label}\n'
        'Support ID: ${ids.analyticsId ?? 'none'}\n'
        'Purchase ID: ${ids.purchaseId ?? 'none'}\n'
        'App version: $appVersion · Platform: $platform\n'
        '(Optional) Google Play order ID: GPA.____\n'
        '\n'
        'Details (optional):\n';
  }

  static Uri uri({
    required PrivacyRequestType type,
    required SupportIds ids,
    required String appVersion,
    required String platform,
    String to = ChainPopLegal.supportEmail,
  }) {
    return Uri(
      scheme: 'mailto',
      path: to,
      // Uri(queryParameters:) encodes spaces as '+', which many mail apps
      // show literally; encode with %20 instead.
      query:
          {
                'subject': subject,
                'body': body(
                  type: type,
                  ids: ids,
                  appVersion: appVersion,
                  platform: platform,
                ),
              }.entries
              .map(
                (e) =>
                    '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
              )
              .join('&'),
    );
  }

  /// Opens the email app with the request pre-filled. [ids] defaults to a
  /// fresh read; pass the receipt's IDs after a deletion (the analytics ID
  /// has already been reset by then). Shows a snackbar if no app opens.
  static Future<void> open(
    BuildContext context, {
    required PrivacyRequestType type,
    SupportIds? ids,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final resolved = ids ?? await SupportIdentity().read();
    final uri = PrivacyRequestEmail.uri(
      type: type,
      ids: resolved,
      appVersion: await _appVersion(),
      platform: _platform(),
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'No email app found. Write to us at ${ChainPopLegal.supportEmail}',
          ),
        ),
      );
    }
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (_) {
      return 'unknown';
    }
  }

  static String _platform() {
    if (kIsWeb) return 'Web';
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iOS';
      return Platform.operatingSystem;
    } catch (_) {
      return 'unknown';
    }
  }
}
