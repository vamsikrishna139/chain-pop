/// Legal / policy URLs — override at build time with `--dart-define`.
///
/// Default points at the Chain Pop hosted policy; CI/staging builds can override
/// with `--dart-define=CHAINPOP_PRIVACY_POLICY_URL=...` when needed.
abstract final class ChainPopLegal {
  static const privacyPolicyUrl = String.fromEnvironment(
    'CHAINPOP_PRIVACY_POLICY_URL',
    defaultValue:
        'https://gist.github.com/vamsikrishna139/426c736eb50f35cb125b37f64259f925',
  );
}
