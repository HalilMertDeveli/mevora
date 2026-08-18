// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appName => 'Mevora';

  @override
  String get tagline => 'Sadece yakındakileri değil, uyumlu insanları bul.';

  @override
  String get connectTagline => 'Sana uyan insanlarla tanış.';

  @override
  String get somethingWentWrong => 'Bir şeyler ters gitti';

  @override
  String get tryAgain => 'Tekrar dene';

  @override
  String get unexpectedError => 'Uygulama beklenmeyen bir hatayla karşılaştı.';

  @override
  String get firebaseUnavailableMessage =>
      'Mevora başlatılamadı. Bağlantını kontrol edip tekrar dene.';

  @override
  String get retry => 'Yeniden dene';

  @override
  String get cancel => 'Vazgeç';

  @override
  String get confirm => 'Onayla';

  @override
  String get close => 'Kapat';

  @override
  String get loading => 'Yükleniyor';

  @override
  String get save => 'Kaydet';

  @override
  String get next => 'İleri';

  @override
  String get back => 'Geri';

  @override
  String get skip => 'Atla';

  @override
  String get continueAction => 'Devam';

  @override
  String get done => 'Tamam';

  @override
  String get you => 'Sen';

  @override
  String get emptyTitle => 'Henüz bir şey yok';

  @override
  String get emptyMessage => 'Gösterilecek bir şey olduğunda burada görünecek.';

  @override
  String get networkError => 'Bağlantını kontrol et ve tekrar dene.';

  @override
  String get notFound => 'Bunu bulamadık.';

  @override
  String get comingSoon => 'Mevora\'nın bu kısmı henüz hazır değil.';

  @override
  String get notAllowed => 'Bu işlem için yetkin yok.';

  @override
  String get needSignIn => 'Devam etmek için giriş yapmalısın.';

  @override
  String get welcomeBack => 'Tekrar hoş geldin';

  @override
  String get loginSubtitle =>
      'Uyumlu insanları keşfetmeye devam etmek için giriş yap.';

  @override
  String get createAccountTitle => 'Hesabını oluştur';

  @override
  String get registerSubtitle =>
      'Bağ kurabileceğin insanlarla tanışmak için Mevora\'ya katıl.';

  @override
  String get email => 'E-posta';

  @override
  String get emailHint => 'sen@email.com';

  @override
  String get emailRequired => 'E-posta gerekli';

  @override
  String get emailInvalid => 'Geçerli bir e-posta gir';

  @override
  String get password => 'Şifre';

  @override
  String get passwordRequired => 'Şifre gerekli';

  @override
  String passwordMinLength(int min) {
    return 'Şifre en az $min karakter olmalı';
  }

  @override
  String get confirmPassword => 'Şifreyi doğrula';

  @override
  String get passwordsDoNotMatch => 'Şifreler eşleşmiyor';

  @override
  String fieldRequired(String field) {
    return '$field gerekli';
  }

  @override
  String fieldMinLength(String field, int min) {
    return '$field en az $min karakter olmalı';
  }

  @override
  String get phoneRequired => 'Telefon gerekli';

  @override
  String get codeRequired => 'Kod gerekli';

  @override
  String get otpInvalidFormat => '6 haneli kodu gir';

  @override
  String get signIn => 'Giriş yap';

  @override
  String get createAccount => 'Hesap oluştur';

  @override
  String get forgotPassword => 'Şifreni mi unuttun?';

  @override
  String get resetPasswordTitle => 'Şifreyi sıfırla';

  @override
  String get resetPasswordMessage =>
      'E-postanı gir, sana bir sıfırlama bağlantısı gönderelim.';

  @override
  String get sendResetLink => 'Sıfırlama bağlantısı gönder';

  @override
  String get resetEmailSentTitle => 'E-postanı kontrol et';

  @override
  String get resetEmailSentMessage =>
      'Bu e-posta ile bir hesap varsa, sıfırlama bağlantısı yolda.';

  @override
  String get backToSignIn => 'Girişe dön';

  @override
  String get orContinueWith => 'veya şununla devam et';

  @override
  String get continueWithGoogle => 'Google ile devam et';

  @override
  String get continueWithApple => 'Apple ile devam et';

  @override
  String get continueWithSpotify => 'Spotify ile devam et';

  @override
  String get continueWithPhone => 'Telefon ile devam et';

  @override
  String get legalPrefix => 'Devam ederek';

  @override
  String get termsOfService => 'Kullanım Koşulları';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get legalConjunction => 've';

  @override
  String get signInWithEmail => 'E-posta ile giriş yap';

  @override
  String get newToMevora => 'Mevora\'da yeni misin?';

  @override
  String get alreadyHaveAccount => 'Zaten hesabın var mı?';

  @override
  String get createAnAccount => 'Hesap oluştur';

  @override
  String get preparingMevora => 'Mevora hazırlanıyor';

  @override
  String get logOut => 'Çıkış yap';

  @override
  String get showPassword => 'Şifreyi göster';

  @override
  String get hidePassword => 'Şifreyi gizle';

  @override
  String get appleSignInUnavailable =>
      'Apple ile giriş iPhone ve iPad\'de kullanılabilir.';

  @override
  String get phoneTitle => 'Telefon numaranı gir';

  @override
  String get phoneSubtitle => 'Doğrulama kodunu SMS ile göndereceğiz.';

  @override
  String get phoneHint => '5xx xxx xx xx';

  @override
  String get sendCode => 'SMS kodu gönder';

  @override
  String get countrySearchHint => 'Ülke ara';

  @override
  String get otpTitle => 'Telefonunu doğrula';

  @override
  String get verify => 'Doğrula';

  @override
  String get resend => 'Kodu tekrar gönder';

  @override
  String get sendingSms => 'SMS gönderiliyor...';

  @override
  String get verifying => 'Doğrulanıyor...';

  @override
  String get phoneVerifiedSuccess => 'Telefon numaran doğrulandı.';

  @override
  String get countryCode => 'Ülke kodu';

  @override
  String get phoneNumber => 'Telefon numarası';

  @override
  String get otpFieldLabel => '6 haneli doğrulama kodu';

  @override
  String otpSentTo(String phone) {
    return '$phone numarasına gönderilen 6 haneli kodu gir.';
  }

  @override
  String resendCountdown(int seconds) {
    return 'Yeni kodu $seconds saniye sonra gönderebilirsin.';
  }

  @override
  String get enterOtp => 'Doğrulama kodunu gir.';

  @override
  String get authCancelled => 'Giriş iptal edildi.';

  @override
  String get authInvalidPhone => 'Geçerli bir telefon numarası gir.';

  @override
  String get authSmsFailed => 'SMS gönderilemedi. Lütfen tekrar dene.';

  @override
  String get authInvalidOtp => 'Doğrulama kodu geçersiz.';

  @override
  String get authExpiredOtp => 'Doğrulama kodunun süresi doldu. Yeni kod iste.';

  @override
  String get authSessionExpired =>
      'Oturumun süresi doldu. Lütfen numarayı tekrar gir.';

  @override
  String get authTooManyAttempts =>
      'Çok fazla hatalı deneme yaptınız. Lütfen daha sonra tekrar deneyin.';

  @override
  String get authSmsQuota =>
      'SMS gönderim limiti aşıldı. Lütfen daha sonra tekrar deneyin.';

  @override
  String get authFirebaseUnavailable =>
      'Doğrulama servisine şu anda ulaşılamıyor. Lütfen daha sonra tekrar dene.';

  @override
  String get authNetwork => 'İnternet bağlantını kontrol et.';

  @override
  String get authDisabled => 'Bu hesap devre dışı bırakılmış.';

  @override
  String get authBanned => 'Bu hesap askıya alındı.';

  @override
  String get authOauth => 'Giriş tamamlanamadı. Lütfen tekrar dene.';

  @override
  String get authUnknown => 'Beklenmeyen bir hata oluştu. Lütfen tekrar dene.';

  @override
  String get authAccountExists =>
      'Bu giriş yöntemi başka bir Mevora hesabına bağlı. Otomatik birleştirme yapılmaz.';

  @override
  String get authLinkingBlocked =>
      'Hesaplar yalnızca sen onayladığında bağlanır. E-posta eşleşmesi yeterli değildir.';

  @override
  String get authNotConfigured => 'Bu giriş yöntemi henüz yapılandırılmadı.';

  @override
  String get authInvalidEmail => 'Geçerli bir e-posta adresi gir.';

  @override
  String get authWeakPassword =>
      'En az 8 karakterlik daha güçlü bir şifre seç.';

  @override
  String get authUserNotFound => 'Bu e-posta ile hesap bulunamadı.';

  @override
  String get authWrongPassword => 'E-posta ve şifre eşleşmiyor.';

  @override
  String get authSpotifyCallbackExpired =>
      'Spotify oturumu zaman aşımına uğradı. Lütfen tekrar dene.';

  @override
  String get authEmailInUse => 'Bu e-posta ile zaten bir hesap var.';

  @override
  String get authGeneric => 'İsteğin tamamlanamadı. Lütfen tekrar dene.';

  @override
  String get authGoogleFailed => 'Google ile giriş tamamlanamadı.';

  @override
  String get authAppleFailed => 'Apple ile giriş tamamlanamadı.';

  @override
  String get onboardingTitle => 'Birkaç adım kaldı';

  @override
  String get onboardingMessage =>
      'Mevora\'nın sana uyumlu insanları önerebilmesi için profilini tamamla.';

  @override
  String get onboardingFirstName => 'Adın';

  @override
  String get onboardingBirthDate => 'Doğum tarihin';

  @override
  String get onboardingGender => 'Ben';

  @override
  String get onboardingInterestedIn => 'İlgilendiğim';

  @override
  String get onboardingCity => 'Şehir';

  @override
  String get onboardingPhotos => 'Profil fotoğrafları';

  @override
  String get onboardingBio => 'Hakkında';

  @override
  String get onboardingInterests => 'İlgi alanları';

  @override
  String get onboardingRelationshipGoal => 'Aradığım';

  @override
  String get onboardingAddPhoto => 'Fotoğraf ekle';

  @override
  String get onboardingMustBeAdult =>
      'Mevora\'yı kullanmak için 18 yaşında veya daha büyük olmalısın.';

  @override
  String get locationPermissionTitle => 'Yakınındaki insanları keşfet';

  @override
  String get locationPermissionMessage =>
      'Mevora, sana daha uygun eşleşmeler gösterebilmek için konumunu kullanır.';

  @override
  String get locationPermissionSub =>
      'Konumun diğer kullanıcılara tam olarak gösterilmez. Yalnızca eşleşme ve mesafe hesaplamalarında kullanılır.';

  @override
  String get useMyLocation => 'Konumumu aç';

  @override
  String get notNow => 'Şimdilik atla';

  @override
  String get locationSkipHint =>
      'Eşleşme ve keşif için konum gerekir. Daha sonra ayarlardan açabilirsin.';

  @override
  String get locationSettingsTitle => 'Konum izni kapalı';

  @override
  String get locationSettingsMessage =>
      'Konum iznini cihaz ayarlarından açabilirsin.';

  @override
  String get openSettings => 'Ayarları aç';

  @override
  String get gpsDisabledTitle => 'Konum hizmetleri kapalı';

  @override
  String get gpsDisabledMessage =>
      'Yakındaki eşleşmeleri gösterebilmemiz için cihazının konum hizmetlerini açman gerekiyor.';

  @override
  String get locationDeniedMessage =>
      'Konum izni olmadan yakınındaki eşleşmeleri gösteremeyiz.';

  @override
  String get locationSuccessTitle =>
      'Harika! Yakınındaki eşleşmeleri bulmaya hazırız.';

  @override
  String get locationLocating => 'Konumun belirleniyor...';

  @override
  String get locationPreparingMatches => 'Yakındaki eşleşmeler hazırlanıyor...';

  @override
  String get locationUnavailableTitle => 'Konum alınamadı';

  @override
  String get locationTimeoutMessage =>
      'Konum isteği zaman aşımına uğradı. Daha sonra tekrar deneyebilirsin.';

  @override
  String get locationNetworkMessage =>
      'Bağlantı sorunu nedeniyle konum kaydedilemedi. Tekrar dene.';

  @override
  String get locationPreciseOffTitle => 'Kesin konum kapalı';

  @override
  String get locationPreciseOffMessage =>
      'Kesin Konum kapalı. Mesafe tahmini yaklaşık olacak; tam koordinatların yine paylaşılmaz.';

  @override
  String get continueWithoutLocation => 'Konumsuz devam et';

  @override
  String get discoveryTitle => 'Eşleşmelerine az kaldı';

  @override
  String get discoveryMessage =>
      'Keşif hazır olduğunda uyumlu insanlar burada görünecek.';

  @override
  String get discoveryEmptyTitle => 'Şu an yeni kimse yok';

  @override
  String get discoveryEmptyMessage =>
      'Mesafeyi genişlet veya biraz sonra tekrar bak.';

  @override
  String get tabDiscovery => 'Keşfet';

  @override
  String get tabMatches => 'Eşleşmeler';

  @override
  String get tabProfile => 'Profil';

  @override
  String get radius => 'Yarıçap';

  @override
  String distanceAway(String distance) {
    return '$distance km uzakta';
  }

  @override
  String get distanceLessThanOne => '1 km\'den yakın';

  @override
  String get distanceFar => '100+ km uzakta';

  @override
  String compatibilityPercent(int percent) {
    return '%$percent uyum';
  }

  @override
  String get like => 'Beğen';

  @override
  String get pass => 'Geç';

  @override
  String get superLike => 'Süper Beğeni';

  @override
  String get itsAMatch => 'Eşleştiniz';

  @override
  String get startChat => 'Merhaba de';

  @override
  String get keepSwiping => 'Keşfetmeye devam et';

  @override
  String get profile => 'Profil';

  @override
  String get editProfile => 'Profili düzenle';

  @override
  String get photos => 'Fotoğraflar';

  @override
  String get bio => 'Hakkında';

  @override
  String get interests => 'İlgi alanları';

  @override
  String get preferences => 'Tercihler';

  @override
  String get account => 'Hesap';

  @override
  String get settings => 'Ayarlar';

  @override
  String get language => 'Dil';

  @override
  String get languageTurkish => 'Türkçe 🇹🇷';

  @override
  String get languageEnglish => 'English 🇬🇧';

  @override
  String get theme => 'Tema';

  @override
  String get help => 'Yardım';

  @override
  String get communityGuidelines => 'Topluluk Kuralları';

  @override
  String get blockedUsers => 'Engellenenler';

  @override
  String get discoveryPreferences => 'Keşif tercihleri';

  @override
  String get minAge => 'En düşük yaş';

  @override
  String get maxAge => 'En yüksek yaş';

  @override
  String get maxDistance => 'En fazla mesafe';

  @override
  String get matchesTitle => 'Eşleşmeler';

  @override
  String get matchesEmptyTitle => 'Henüz eşleşme yok';

  @override
  String get matchesEmptyMessage =>
      'Karşılıklı beğeniler burada sohbet olarak görünür.';

  @override
  String get newMatch => 'Yeni eşleşme';

  @override
  String get chatHint => 'Mesaj yaz...';

  @override
  String get send => 'Gönder';

  @override
  String get typing => 'yazıyor...';

  @override
  String get unmatchedBanner => 'Bu kişiyle eşleşmeniz kaldırıldı.';

  @override
  String get videoCall => 'Görüntülü ara';

  @override
  String get more => 'Daha fazla';

  @override
  String get cannotMessageSelf => 'Kendine mesaj gönderemezsin.';

  @override
  String get blockedInteraction => 'Bu kişiyle mesajlaşamazsın.';

  @override
  String get matchInactive => 'Bu kişiyle eşleşmeniz kaldırıldı.';

  @override
  String get notMatched => 'Yalnızca eşleştiğin kişilerle yazabilirsin.';

  @override
  String get alreadySwiped => 'Bu kişiyi zaten değerlendirdin.';

  @override
  String get chatNotFound => 'Sohbet bulunamadı.';

  @override
  String get chatGeneric => 'Mesaj gönderilemedi. Lütfen tekrar dene.';

  @override
  String get incomingCall => 'Gelen görüntülü arama';

  @override
  String get accept => 'Kabul et';

  @override
  String get decline => 'Reddet';

  @override
  String get endCall => 'Bitir';

  @override
  String get mute => 'Sessiz';

  @override
  String get unmute => 'Sesi aç';

  @override
  String get cameraOn => 'Kamerayı aç';

  @override
  String get cameraOff => 'Kamerayı kapat';

  @override
  String get speaker => 'Hoparlör';

  @override
  String get switchCamera => 'Kamerayı çevir';

  @override
  String get userBusy => 'Kişi şu anda başka bir aramada.';

  @override
  String get callNotConfigured => 'Görüntülü arama şu anda kullanılamıyor.';

  @override
  String get cameraDenied =>
      'Kamera izni olmadan görüntülü arama başlatılamaz.';

  @override
  String get micDenied => 'Mikrofon izni olmadan arama başlatılamaz.';

  @override
  String get connectionUnstable => 'Bağlantı dengesiz';

  @override
  String get reconnecting => 'Yeniden bağlanılıyor…';

  @override
  String get callFailed => 'Arama bağlanamadı. Lütfen tekrar dene.';

  @override
  String get callEnded => 'Arama sona erdi';

  @override
  String get connecting => 'Bağlanıyor…';

  @override
  String get calling => 'Aranıyor…';

  @override
  String get ringing => 'Çalıyor…';

  @override
  String get missedCall => 'Cevapsız görüntülü arama';

  @override
  String get callPermissionTitle => 'Kamera ve mikrofon';

  @override
  String get callPermissionBody =>
      'Görüntülü arama için kamera ve mikrofon izni gerekir.';

  @override
  String get presenceOnline => 'Çevrimiçi';

  @override
  String get presenceRecentlyActive => 'Yakınlarda aktif';

  @override
  String get presenceOffline => 'Çevrimdışı';

  @override
  String get timeNow => 'şimdi';

  @override
  String timeMinutes(int count) {
    return '$count dk';
  }

  @override
  String timeHours(int count) {
    return '$count sa';
  }

  @override
  String timeDays(int count) {
    return '$count g';
  }

  @override
  String get unmatch => 'Eşleşmeyi kaldır';

  @override
  String get unmatchConfirmTitle => 'Eşleşme kaldırılsın mı?';

  @override
  String get unmatchConfirmMessage =>
      'Bu kişiyle artık mesajlaşamazsın. Bu işlem sohbeti kapatır.';

  @override
  String get block => 'Engelle';

  @override
  String get blockConfirmTitle => 'Bu kişiyi engelle?';

  @override
  String get blockConfirmMessage =>
      'Engellenen kişi keşiften gizlenir, mesaj ve arama yapılamaz.';

  @override
  String get report => 'Şikayet et';

  @override
  String get reportTitle => 'Şikayet nedeni';

  @override
  String get reportDescription => 'Açıklama (isteğe bağlı)';

  @override
  String get submitReport => 'Şikayeti gönder';

  @override
  String get reportThanks => 'Şikayetin alındı.';

  @override
  String get offerBlockTitle => 'Bu kişiyi de engellemek ister misin?';

  @override
  String get offerBlockMessage =>
      'Engellemek yeni mesaj, eşleşme ve aramaları durdurur.';

  @override
  String get reportSpam => 'Spam';

  @override
  String get reportHarassment => 'Taciz';

  @override
  String get reportInappropriate => 'Uygunsuz içerik';

  @override
  String get reportScam => 'Dolandırıcılık';

  @override
  String get reportFakeProfile => 'Sahte profil';

  @override
  String get reportUnderage => 'Reşit değil';

  @override
  String get reportOther => 'Diğer';

  @override
  String get linkedAccounts => 'Bağlı hesaplar';

  @override
  String get link => 'Bağla';

  @override
  String get linked => 'Bağlı';

  @override
  String get deleteAccount => 'Hesabı sil';

  @override
  String get deleteAccountTitle => 'Hesabın silinsin mi?';

  @override
  String get deleteAccountBody =>
      'Mevora hesabın, profilin, eşleşmelerin ve mesajların kalıcı olarak silinir. Bu işlem geri alınamaz.';

  @override
  String get deleteConfirm => 'Kalıcı olarak sil';

  @override
  String get notificationsTitle => 'Bildirimler ve gizlilik';

  @override
  String get messageNotifications => 'Mesaj bildirimleri';

  @override
  String get matchNotifications => 'Eşleşme bildirimleri';

  @override
  String get callNotifications => 'Arama bildirimleri';

  @override
  String get hideOnlineStatus => 'Çevrimiçi durumunu gizle';

  @override
  String get notificationNewMatch => 'Yeni bir eşleşmen var!';

  @override
  String get notificationNewMessage => 'Yeni bir mesajın var';

  @override
  String get notificationSuperLike => 'Birisi seni Süper Beğendi';

  @override
  String get boostTitle => 'BOOST';

  @override
  String get boostSubtitle =>
      'Profilini daha fazla kişiye göster ve keşfedilme şansını artır.';

  @override
  String get boostDuration => '30 dakika';

  @override
  String get boostActivate => 'Boost\'u aktif et';

  @override
  String get boostBuy => 'Boost\'u satın al';

  @override
  String get boostPurchasing => 'Satın alma işlemi başlatılıyor...';

  @override
  String get boostVerifying => 'Satın alma doğrulanıyor...';

  @override
  String get boostSuccessTitle => 'Boost aktif! 🚀';

  @override
  String get boostSuccessMessage =>
      'Profilin daha fazla kişiye gösterilmeye başlayacak.';

  @override
  String get boostAlreadyActive => 'Zaten aktif bir Boost\'un var.';

  @override
  String get boostPurchaseCancelled => 'Satın alma iptal edildi.';

  @override
  String get boostPurchaseFailed =>
      'Satın alma tamamlanamadı. Lütfen tekrar dene.';

  @override
  String get boostStoreUnavailable =>
      'Mağaza şu anda bu cihazda kullanılamıyor.';

  @override
  String get boostStoreDown =>
      'Mağaza şu anda yanıt vermiyor. Biraz sonra tekrar dene.';

  @override
  String get boostNetworkError =>
      'Bağlantı sorunu nedeniyle satın alma doğrulanamadı.';

  @override
  String get boostVerificationFailed =>
      'Satın alma doğrulanamadı. Biraz sonra tekrar dene.';

  @override
  String get boostAlreadyProcessed => 'Bu satın alma zaten işlendi.';

  @override
  String get boostLoadingProduct => 'Mağaza bilgileri yükleniyor...';

  @override
  String get boostBackToDiscovery => 'Keşfe dön';

  @override
  String get boostTooltip => 'Boost';

  @override
  String boostRemainingMinutes(int minutes) {
    return '$minutes dk';
  }

  @override
  String radiusKm(int km) {
    return '$km km';
  }

  @override
  String get paymentTitle => 'Ödeme';

  @override
  String get paymentProcessing => 'Ödeme işleniyor...';

  @override
  String get paymentSuccess => 'Ödeme başarılı.';

  @override
  String get paymentFailed => 'Ödeme başarısız. Lütfen tekrar dene.';

  @override
  String get restorePurchases => 'Satın almaları geri yükle';

  @override
  String get startupUnavailable =>
      'Mevora başlatılamadı. Bağlantını kontrol et ve tekrar dene.';
}
