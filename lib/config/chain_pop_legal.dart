/// Legal / policy URLs — override at build time with `--dart-define`.
///
/// Replace `CHAINPOP_PRIVACY_POLICY_URL` with your hosted privacy policy before
/// production Play / App Store submission.
abstract final class ChainPopLegal {
  static const privacyPolicyUrl = String.fromEnvironment(
    'CHAINPOP_PRIVACY_POLICY_URL',
    defaultValue: 'https://example.com/chain-pop/privacy-policy',
  );
}
