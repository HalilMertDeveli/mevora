/// What the client needs to launch a provider verification flow, and nothing
/// more.
///
/// Deliberately absent: API keys, webhook secrets, workflow ids and any
/// provider credential. The backend creates the session and hands back only
/// these handles; none of them is authority over the result.
class IdentityVerificationSession {
  const IdentityVerificationSession({
    required this.providerSessionId,
    this.launchToken,
    this.launchUrl,
  });

  /// The provider's session reference, echoed so the client can correlate a
  /// resumed flow. Not a secret, and not proof of anything.
  final String providerSessionId;

  /// A short-lived token for a native SDK launch, when the provider uses one.
  final String? launchToken;

  /// A hosted verification URL, when the provider uses one instead.
  final String? launchUrl;

  bool get canLaunch =>
      (launchToken != null && launchToken!.isNotEmpty) ||
      (launchUrl != null && launchUrl!.isNotEmpty);
}
