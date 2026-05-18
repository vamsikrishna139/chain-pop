/// Legal / policy URLs — override at build time with `--dart-define`.
///
/// Default points at the Chain Pop hosted policy; CI/staging builds can override
/// with `--dart-define=CHAINPOP_PRIVACY_POLICY_URL=...` when needed.
abstract final class ChainPopLegal {
  static const privacyPolicyUrl = String.fromEnvironment(
    'CHAINPOP_PRIVACY_POLICY_URL',
    defaultValue: 'https://sites.google.com/view/mindglow-studios/home',
  );

  /// Note: If you change this email, you must also manually update the contact
  /// email address in `docs/privacy.md`.
  static const supportEmail = String.fromEnvironment(
    'CHAINPOP_SUPPORT_EMAIL',
    defaultValue: 'adbkv.apps@gmail.com',
  );
}
