import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/chain_pop_legal.dart';
import '../../../services/ads/ump_consent.dart';
import '../../../services/privacy/data_deletion_service.dart';
import '../../../services/privacy/privacy_request_email.dart';
import '../../../services/privacy/support_identity.dart';
import '../../../theme/app_colors.dart';

/// Opens a privacy request email. Injectable for widget tests.
typedef PrivacyEmailLauncher = Future<void> Function(
  BuildContext context,
  PrivacyRequestType type,
  SupportIds? ids,
);

Future<void> _defaultEmailLauncher(
  BuildContext context,
  PrivacyRequestType type,
  SupportIds? ids,
) => PrivacyRequestEmail.open(context, type: type, ids: ids);

/// A simple, plain-language breakdown of user privacy rights, bridging
/// gameplay functionality with AdMob/CMP requirements.
///
/// "Delete my data" is offered only when [onDataDeleted] is given — i.e. from
/// the home screen, like "Reset Game Data", never under an open level.
Future<void> showPrivacyRightsSheet({
  required BuildContext context,
  required Color accent,
  required bool showAdChoicesButton,
  VoidCallback? onDataDeleted,
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
          return PrivacyRightsContent(
            scrollController: scrollController,
            accent: accent,
            showAdChoicesButton: showAdChoicesButton,
            onDataDeleted: onDataDeleted,
          );
        },
      );
    },
  );
}

class PrivacyRightsContent extends StatefulWidget {
  const PrivacyRightsContent({
    super.key,
    required this.accent,
    required this.showAdChoicesButton,
    this.scrollController,
    this.onDataDeleted,
    this.identity,
    this.deletionService,
    this.emailLauncher = _defaultEmailLauncher,
  });

  final Color accent;
  final bool showAdChoicesButton;
  final ScrollController? scrollController;
  final VoidCallback? onDataDeleted;
  final SupportIdentity? identity;
  final DataDeletionService? deletionService;
  final PrivacyEmailLauncher emailLauncher;

  @override
  State<PrivacyRightsContent> createState() => _PrivacyRightsContentState();
}

class _PrivacyRightsContentState extends State<PrivacyRightsContent> {
  late Future<SupportIds> _ids;

  @override
  void initState() {
    super.initState();
    _ids = (widget.identity ?? SupportIdentity()).read();
  }

  Future<void> _email(PrivacyRequestType type, [SupportIds? ids]) =>
      widget.emailLauncher(context, type, ids);

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDialog,
        title: const Text('Delete data on this device?'),
        content: const Text(
          'Your progress, stars and settings will be erased and your '
          'analytics ID reset. Your ad-free purchase and privacy choices are '
          "kept. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final receipt = await (widget.deletionService ?? DataDeletionService())
        .deleteMyData();
    widget.onDataDeleted?.call();
    if (!mounted) return;
    final refreshed = (widget.identity ?? SupportIdentity()).read();
    setState(() {
      _ids = refreshed;
    });

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDialog,
        title: const Text('Done'),
        content: const Text(
          'Data on this device is deleted. To also delete copies held by our '
          'analytics and purchase providers, send the pre-filled request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send deletion request'),
          ),
        ],
      ),
    );
    if (send == true && mounted) {
      await _email(PrivacyRequestType.delete, receipt.previousIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: CustomScrollView(
          controller: widget.scrollController,
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
                    'Unbound is playable without an account. We store game progress, settings, and puzzle activity locally on your device. Ads and diagnostics may use device identifiers, usage data, and approximate region to show, measure, and improve ads.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  const _Section(
                    title: 'Ad Choices',
                    content: 'Change consent for personalized ads and ad measurement where available.',
                  ),
                  if (widget.showAdChoicesButton)
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
                              color: accent.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  const _Section(
                    title: 'Your Data',
                    content: 'Game progress is stored on your device. Achievements sync to Google Play Games if you sign in; purchases are recorded by Google Play and RevenueCat. Analytics and ad data may be sent to Google to keep the game healthy and serve ads.',
                  ),
                  const SizedBox(height: 24),
                  const _Section(
                    title: 'Your Rights',
                    content: 'Depending on where you live, you have the right to access, correct, or delete your data, and opt-out of targeted advertising. Use the buttons below or Delete my data. We reply within 30 days.',
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(ChainPopLegal.privacyPolicyUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      },
                      icon: const Icon(
                        Icons.article_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: const Text(
                        'Read full privacy policy',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FutureBuilder<SupportIds>(
                    future: _ids,
                    builder: (context, snap) =>
                        _SupportIdRow(ids: snap.data, loading: !snap.hasData),
                  ),
                  const SizedBox(height: 24),
                  const _Section(
                    title: 'Contact',
                    content: 'Have questions about your data or wish to exercise your rights?',
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _email(PrivacyRequestType.access),
                      icon: const Icon(
                        Icons.download_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: const Text(
                        'Request a copy of my data',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _email(PrivacyRequestType.other),
                      icon: const Icon(
                        Icons.email_outlined,
                        color: Colors.white70,
                        size: 18,
                      ),
                      label: const Text(
                        'Other request',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (widget.onDataDeleted != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed: _confirmDelete,
                        icon: const Icon(
                          Icons.delete_forever_outlined,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        label: const Text(
                          'Delete my data',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Delete my data is available from Settings on the home screen.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => launchUrl(
                        Uri.parse('https://myaccount.google.com'),
                        mode: LaunchMode.externalApplication,
                      ),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: const Text(
                        'Achievements are managed in your Google Play Games profile (myaccount.google.com).',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.white24,
                        ),
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
  }
}

class _SupportIdRow extends StatelessWidget {
  const _SupportIdRow({required this.ids, required this.loading});

  final SupportIds? ids;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final full = ids?.analyticsId;
    final short = ids?.shortId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Your Support ID',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                loading ? '…' : (short ?? 'None (no analytics ID on this device)'),
                key: const ValueKey('supportIdValue'),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: short == null ? 14 : 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: short == null ? null : 'monospace',
                  letterSpacing: short == null ? 0 : 1.5,
                ),
              ),
            ),
            if (full != null)
              IconButton(
                tooltip: 'Copy Support ID',
                icon: const Icon(
                  Icons.copy_rounded,
                  color: Colors.white70,
                  size: 20,
                ),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.maybeOf(context);
                  await Clipboard.setData(ClipboardData(text: full));
                  messenger?.showSnackBar(
                    const SnackBar(content: Text('Support ID copied')),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Include this when contacting us so we can find your data.',
          style: TextStyle(color: Colors.white60, height: 1.4, fontSize: 14),
        ),
      ],
    );
  }
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
