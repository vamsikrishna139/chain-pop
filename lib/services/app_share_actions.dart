import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/chain_pop_legal.dart';
import 'analytics/analytics_locator.dart';

/// "Share app" and "Send feedback" actions used by the main menu, the
/// settings sheet and the win panel.
abstract final class AppShareActions {
  static const playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.adbkv.chainpop';

  /// Opens the system share sheet with a short pitch and the store link.
  static Future<void> shareApp({required String source}) async {
    unawaited(AnalyticsLocator.instance.logShareAppTapped(source: source));
    try {
      await SharePlus.instance.share(ShareParams(
        text: "I've been playing Unbound: Arrow Puzzle, a chain-reaction "
            'logic puzzle. Try it: $playStoreUrl',
      ));
    } catch (_) {}
  }

  /// Share text for a cleared level; always carries the store link so the
  /// recipient can install the game.
  static String levelClearedShareText(String levelId) =>
      'I just completed Level $levelId in Unbound! Can you beat my time? '
      '$playStoreUrl';

  /// Opens the email app addressed to the support inbox. Falls back to a
  /// snackbar with the address when no email app can handle it.
  static Future<void> sendFeedback(BuildContext context) async {
    unawaited(AnalyticsLocator.instance.logFeedbackTapped());
    final messenger = ScaffoldMessenger.maybeOf(context);
    const email = ChainPopLegal.supportEmail;
    final version = await _appVersion();
    final device = await _deviceDescription();
    final uri = Uri(
      scheme: 'mailto',
      path: email,
      query: _encodeQuery({
        'subject': 'Unbound feedback (v$version)',
        'body': '\n\n---\nApp: $version\nDevice: $device\n',
      }),
    );
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened) {
      messenger?.showSnackBar(
        const SnackBar(
            content: Text('No email app found. Write to us at $email')),
      );
    }
  }

  /// e.g. "1.0.0+8"; read from the build so it never goes stale.
  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return 'unknown';
    }
  }

  /// e.g. "Google Pixel 8a, Android 16 (API 36)".
  static Future<String> _deviceDescription() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        return '${a.manufacturer} ${a.model}, '
            'Android ${a.version.release} (API ${a.version.sdkInt})';
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return '${i.utsname.machine}, ${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}
    return Platform.operatingSystemVersion;
  }

  // Uri(queryParameters:) encodes spaces as '+', which many mail apps show
  // literally; encode with %20 instead.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
