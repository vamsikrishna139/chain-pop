import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/chain_pop_legal.dart';
import '../../../services/ads/ump_consent.dart';
import '../../../theme/app_colors.dart';

/// A simple, plain-language breakdown of user privacy rights, bridging
/// gameplay functionality with AdMob/CMP requirements.
Future<void> showPrivacyRightsSheet({
  required BuildContext context,
  required Color accent,
  required bool showAdChoicesButton,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDialog,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scrollController) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Privacy Rights',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Chain Pop is playable without an account. We store game progress, settings, and puzzle activity locally on your device. Ads and diagnostics may use device identifiers, usage data, and approximate region to show, measure, and improve ads.',
                          style: TextStyle(
                            color: Colors.white70,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'Ad Choices',
                          content:
                              'Change consent for personalized ads and ad measurement where available.',
                        ),
                        if (showAdChoicesButton)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                  showPrivacyOptionsForm();
                                },
                                icon: Icon(Icons.tune, size: 18, color: accent),
                                label: Text(
                                  'Manage ad choices',
                                  style: TextStyle(color: accent),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                      color: accent.withValues(alpha: 0.5)),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'Your Data',
                          content:
                              'Game progress is stored strictly on your device. Analytical and ad-related data may be transmitted to Google and partners to ensure game health and serve relevant content.',
                        ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'Your Rights',
                          content:
                              'Depending on where you live, you have the right to access, correct, or delete your data, and opt-out of targeted advertising. Please view our full privacy policy for detailed instructions.',
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () async {
                              final uri =
                                  Uri.parse(ChainPopLegal.privacyPolicyUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon: Icon(Icons.article_outlined,
                                color: Colors.white70, size: 18),
                            label: const Text(
                              'Read full privacy policy',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        _Section(
                          title: 'Contact',
                          content:
                              'Have questions about your data or wish to exercise your rights?',
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () async {
                              final uri = Uri(
                                scheme: 'mailto',
                                path: ChainPopLegal.supportEmail,
                                queryParameters: {
                                  'subject': 'Privacy Inquiry - Chain Pop'
                                },
                              );
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            icon: Icon(Icons.email_outlined,
                                color: Colors.white70, size: 18),
                            label: const Text(
                              'Request privacy help',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          content,
          style: const TextStyle(
            color: Colors.white60,
            height: 1.4,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
