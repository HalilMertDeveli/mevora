/// User-facing authentication copy. Errors are always Turkish; never expose
/// raw `firebase_auth/` codes.
abstract final class AuthMessages {
  static const String brand = 'MEVORA';
  static const String tagline = 'Connect with people who match you.';
  static const String continueGoogle = 'Continue with Google';
  static const String continueApple = 'Continue with Apple';
  static const String continueSpotify = 'Continue with Spotify';
  static const String continuePhone = 'Sign in with Phone Number';
  static const String legalPrefix = 'By continuing you agree to our';
  static const String termsOfService = 'Terms of Service';
  static const String privacyPolicy = 'Privacy Policy';
  static const String legalConjunction = 'and';
  static const String phoneTitle = 'Telefon Numarası ile Giriş Yap';
  static const String phoneSubtitle =
      'Ülke kodunu seçip telefon numaranı gir. Doğrulama için SMS ile 6 haneli bir kod göndereceğiz.';
  static const String phoneHint = '0542 519 2119';
  static const String sendCode = 'Doğrulama kodu gönder';
  static const String countrySearchHint = 'Ülke ara';
  static const String otpTitle = 'Doğrulama kodunu gir';
  static const String verify = 'Doğrula';
  static const String resend = 'Kodu Tekrar Gönder';
  static const String sendingSms = 'SMS gönderiliyor...';
  static const String verifying = 'Doğrulanıyor...';
  static const String phoneVerifiedSuccess = 'Telefon numaran doğrulandı.';
  static const String countrySelectorLabel = 'Ülke kodu';
  static const String phoneFieldLabel = 'Telefon numarası';
  static const String otpFieldLabel = '6 haneli doğrulama kodu';
  static const String back = 'Geri';
  static const String logout = 'Log out';
  static const String deleteAccount = 'Delete account';
  static const String deleteAccountTitle = 'Delete your account?';
  static const String deleteAccountBody =
      'This permanently deletes your Mevora account, profile, matches, and messages. This cannot be undone.';
  static const String deleteConfirm = 'Delete forever';
  static const String linkedAccounts = 'Linked accounts';
  static const String link = 'Link';
  static const String linked = 'Linked';
  static const String cancel = 'Cancel';

  static const String cancelled = 'Giriş iptal edildi.';
  static const String invalidPhone = 'Telefon numarası geçersiz.';
  static const String smsFailed =
      'SMS gönderilemedi. Lütfen tekrar dene.';
  static const String appVerification =
      'Uygulama doğrulaması tamamlanamadı. İnternet bağlantını kontrol et, gerçek bir cihazda dene ve birkaç saniye sonra yeniden dene.';
  static const String invalidOtp = 'Doğrulama kodu hatalı.';
  static const String expiredOtp =
      'Doğrulama kodunun süresi doldu. Yeni kod isteyin.';
  static const String sessionExpired =
      'Oturumun süresi doldu. Lütfen numarayı tekrar gir.';
  static const String tooManyAttempts =
      'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.';
  static const String smsQuota =
      'SMS gönderim limiti aşıldı. Lütfen daha sonra tekrar deneyin.';
  static const String firebaseUnavailable =
      'Doğrulama servisine şu anda ulaşılamıyor. Lütfen daha sonra tekrar dene.';
  static const String smsInFlight =
      'SMS isteği zaten gönderiliyor. Lütfen kısa süre bekle.';
  static const String network = 'İnternet bağlantını kontrol et.';
  static const String disabled = 'Bu hesap devre dışı bırakılmış.';
  static const String banned = 'Bu hesap askıya alındı.';
  static const String oauth = 'Giriş tamamlanamadı. Lütfen tekrar dene.';
  static const String unknown =
      'Beklenmeyen bir hata oluştu. Lütfen tekrar dene.';
  static const String accountExists =
      'Bu giriş yöntemi başka bir Mevora hesabına bağlı. Otomatik birleştirme yapılmaz.';
  static const String linkingBlocked =
      'Hesaplar yalnızca sen onayladığında bağlanır. E-posta eşleşmesi yeterli değildir.';
  static const String notConfigured =
      'Telefon ile giriş henüz Firebase’de etkin değil.';
  static const String billingNotEnabled =
      'SMS gönderimi için Firebase faturalandırması (Blaze) gerekli.';
  static const String invalidEmail = 'Geçerli bir e-posta adresi gir.';
  static const String weakPassword =
      'En az 8 karakterlik daha güçlü bir şifre seç.';
  static const String userNotFound = 'Bu e-posta ile hesap bulunamadı.';
  static const String wrongPassword = 'E-posta ve şifre eşleşmiyor.';
  static const String emailInUse = 'Bu e-posta ile zaten bir hesap var.';
  static const String spotifyCallbackExpired =
      'Spotify oturumu zaman aşımına uğradı. Lütfen tekrar dene.';

  static String resendCountdown(int seconds) {
    return 'Yeni kodu $seconds saniye sonra tekrar gönderebilirsin.';
  }

  static String otpSentTo(String maskedPhone) {
    return '$maskedPhone numarasına gönderilen 6 haneli kodu gir.';
  }
}
