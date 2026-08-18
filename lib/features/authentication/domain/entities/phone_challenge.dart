class PhoneChallenge {
  const PhoneChallenge({
    required this.verificationId,
    required this.e164Phone,
    required this.maskedPhone,
    this.resendToken,
    this.resendAttempt = 0,
    this.autoVerified = false,
  });

  final String verificationId;
  final String e164Phone;
  final String maskedPhone;
  final int? resendToken;
  final int resendAttempt;
  final bool autoVerified;

  PhoneChallenge copyWith({
    String? verificationId,
    int? resendToken,
    int? resendAttempt,
    bool? autoVerified,
  }) {
    return PhoneChallenge(
      verificationId: verificationId ?? this.verificationId,
      e164Phone: e164Phone,
      maskedPhone: maskedPhone,
      resendToken: resendToken ?? this.resendToken,
      resendAttempt: resendAttempt ?? this.resendAttempt,
      autoVerified: autoVerified ?? this.autoVerified,
    );
  }
}
