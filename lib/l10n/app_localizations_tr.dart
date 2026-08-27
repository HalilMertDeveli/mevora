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
  String get loginSlogan =>
      'Sadece insanları değil,\nsana uygun insanları keşfet.';

  @override
  String get continueWithEmail => 'E-posta ile devam et';

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
  String get loginSubtitle => 'Keşfetmeye devam etmek için giriş yap.';

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
  String get signingIn => 'Giriş yapılıyor...';

  @override
  String get continueWithApple => 'Apple ile devam et';

  @override
  String get continueWithSpotify => 'Spotify ile devam et';

  @override
  String get continueWithPhone => 'Telefon Numarası ile Giriş Yap';

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
  String get phoneTitle => 'Telefon Numarası ile Giriş Yap';

  @override
  String get phoneSubtitle =>
      'Ülke kodunu seçip telefon numaranı gir. Doğrulama için SMS ile 6 haneli bir kod göndereceğiz.';

  @override
  String get phoneHint => '0542 519 2119';

  @override
  String get sendCode => 'Doğrulama kodu gönder';

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
  String get authInvalidPhone => 'Telefon numarası geçersiz.';

  @override
  String get authSmsFailed => 'SMS gönderilemedi. Lütfen tekrar dene.';

  @override
  String get authAppVerification =>
      'Uygulama doğrulaması tamamlanamadı. İnternet bağlantını kontrol et, gerçek bir cihazda dene ve birkaç saniye sonra yeniden dene.';

  @override
  String get authInvalidOtp => 'Doğrulama kodu hatalı.';

  @override
  String get authExpiredOtp =>
      'Doğrulama kodunun süresi doldu. Yeni kod isteyin.';

  @override
  String get authSessionExpired =>
      'Oturumun süresi doldu. Lütfen numarayı tekrar gir.';

  @override
  String get authTooManyAttempts =>
      'Çok fazla deneme yapıldı. Lütfen daha sonra tekrar deneyin.';

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
  String get authNotConfigured =>
      'Telefon ile giriş henüz Firebase’de etkin değil.';

  @override
  String get authBillingNotEnabled =>
      'SMS gönderimi için Firebase faturalandırması (Blaze) gerekli.';

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
  String get googleSignInCancelled => 'Google ile giriş iptal edildi.';

  @override
  String get googleSignInFailed => 'Google ile giriş tamamlanamadı.';

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
  String onboardingStepProgress(int current, int total) {
    return 'Adım $current / $total';
  }

  @override
  String get onboardingBack => 'Geri';

  @override
  String get onboardingContinue => 'Devam Et';

  @override
  String get onboardingEducation => 'Eğitim';

  @override
  String get onboardingLifestyle => 'Yaşam tarzı';

  @override
  String get onboardingSmoking => 'Sigara';

  @override
  String get onboardingDrinking => 'Alkol';

  @override
  String get onboardingExercise => 'Egzersiz';

  @override
  String get onboardingPets => 'Evcil hayvan';

  @override
  String get onboardingInterestsHint =>
      'Profilini tamamlamak için en az 3 ilgi alanı seç.';

  @override
  String get onboardingBioHint => 'Kendinden biraz bahset.';

  @override
  String get onboardingPhotosHint =>
      'En az 3 fotoğraf ekle. Sıralamak için sürükle — ilk fotoğraf ana fotoğrafındır.';

  @override
  String get onboardingPrimaryPhoto => 'Ana fotoğraf';

  @override
  String onboardingPhotoNumber(int number) {
    return 'Fotoğraf $number';
  }

  @override
  String get onboardingCompleteTitle => 'Hazırsın';

  @override
  String get onboardingCompleteMessage =>
      'Profilin hazır. Mevora uyumlu kişilerle tanıştırmaya başlayacak.';

  @override
  String get onboardingStartDiscovering => 'Keşfetmeye başla';

  @override
  String get onboardingGenderMan => 'Erkek';

  @override
  String get onboardingGenderWoman => 'Kadın';

  @override
  String get onboardingGenderNonBinary => 'Non-binary';

  @override
  String get onboardingInterestedMen => 'Erkekler';

  @override
  String get onboardingInterestedWomen => 'Kadınlar';

  @override
  String get onboardingInterestedEveryone => 'Herkes';

  @override
  String get onboardingEducationHighSchool => 'Lise';

  @override
  String get onboardingEducationSomeCollege => 'Üniversite (devam)';

  @override
  String get onboardingEducationBachelors => 'Lisans';

  @override
  String get onboardingEducationMasters => 'Yüksek lisans';

  @override
  String get onboardingEducationPhd => 'Doktora';

  @override
  String get onboardingEducationPreferNotToSay => 'Belirtmek istemiyorum';

  @override
  String get onboardingRelationshipLongTerm => 'Uzun süreli ilişki';

  @override
  String get onboardingRelationshipShortTerm => 'Kısa süreli ilişki';

  @override
  String get onboardingRelationshipFriendship => 'Yeni arkadaşlar';

  @override
  String get onboardingRelationshipNotSure => 'Henüz emin değilim';

  @override
  String get onboardingRelationshipPreferNotToSay => 'Belirtmek istemiyorum';

  @override
  String get onboardingLifestyleNever => 'Asla';

  @override
  String get onboardingLifestyleSometimes => 'Bazen';

  @override
  String get onboardingLifestyleRegularly => 'Düzenli';

  @override
  String get onboardingLifestyleDaily => 'Her gün';

  @override
  String get onboardingLifestyleNone => 'Yok';

  @override
  String get onboardingLifestyleCat => 'Kedi';

  @override
  String get onboardingLifestyleDog => 'Köpek';

  @override
  String get onboardingLifestyleBoth => 'İkisi de';

  @override
  String get onboardingLifestyleOther => 'Diğer';

  @override
  String get onboardingAlcoholNone => 'Hiç kullanmıyorum';

  @override
  String get onboardingAlcoholRarely => 'Nadiren';

  @override
  String get onboardingAlcoholSocial => 'Sosyal olarak';

  @override
  String get onboardingAlcoholSpecialOccasion => 'Özel günlerde';

  @override
  String get onboardingAlcoholFrequently => 'Sık sık';

  @override
  String get interestMusic => 'Müzik';

  @override
  String get interestTravel => 'Seyahat';

  @override
  String get interestFitness => 'Fitness';

  @override
  String get interestFood => 'Yemek';

  @override
  String get interestArt => 'Sanat';

  @override
  String get interestMovies => 'Filmler';

  @override
  String get interestBooks => 'Kitaplar';

  @override
  String get interestGaming => 'Oyun';

  @override
  String get interestNature => 'Doğa';

  @override
  String get interestPhotography => 'Fotoğraf';

  @override
  String get interestCoffee => 'Kahve';

  @override
  String get interestDancing => 'Dans';

  @override
  String get interestYoga => 'Yoga';

  @override
  String get interestTech => 'Teknoloji';

  @override
  String get interestFashion => 'Moda';

  @override
  String get interestPets => 'Evcil hayvan';

  @override
  String get interestSports => 'Spor';

  @override
  String get interestCooking => 'Yemek yapma';

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
  String get discoverySeenEveryoneTitle => 'Şimdilik burada herkes bu kadar.';

  @override
  String get discoverySeenEveryoneMessage =>
      'Yeni kişiler için daha sonra tekrar bak veya demoyu yeniden başlat.';

  @override
  String get exploreAgain => 'Tekrar keşfet';

  @override
  String get restartDemo => 'Demoyu yeniden başlat';

  @override
  String get discoveryFiltersTitle => 'Keşif filtreleri';

  @override
  String get discoveryFiltersHint =>
      'Filtreler yerel olarak kaydedilir. Sunucu tarafı filtreleme sonraki güncellemede gelecek.';

  @override
  String get applyFilters => 'Filtreleri uygula';

  @override
  String get filterAge => 'Yaş aralığı';

  @override
  String get filterDistance => 'Maksimum mesafe';

  @override
  String get filterGender => 'Göster';

  @override
  String get filterRelationshipGoal => 'İlişki hedefi';

  @override
  String get genderWoman => 'Kadın';

  @override
  String get genderMan => 'Erkek';

  @override
  String get genderNonBinary => 'Non-binary';

  @override
  String get relationshipGoalLongTerm => 'Uzun vadeli';

  @override
  String get relationshipGoalCasual => 'Gündelik';

  @override
  String get relationshipGoalFiguringOut => 'Henüz kararsızım';

  @override
  String get compatibilityReasonsHeading => 'Neden önerildi';

  @override
  String get whyYoureSeeingThis => 'Bu profil neden gösteriliyor';

  @override
  String get sharedInterests => 'Ortak ilgi alanları';

  @override
  String get profileDetailsTitle => 'Profil';

  @override
  String photoCounter(int current, int total) {
    return '$current / $total';
  }

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
    return 'Önerilen · %$percent uyum';
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
  String get youLikedEachOther => 'Birbirinizi beğendiniz!';

  @override
  String get sendMessage => 'Mesaj gönder';

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
  String get matchesEmptyTitle => 'Henüz bir eşleşmen yok.';

  @override
  String get matchesEmptyMessage =>
      'Karşılıklı beğeniler burada sohbet olarak görünür.';

  @override
  String get newMatch => 'Yeni eşleşme';

  @override
  String get chatHint => 'Mesaj yaz...';

  @override
  String get chatEmptyTitle => 'Henüz mesaj yok';

  @override
  String get chatEmptyMessage => 'İlk mesajı sen gönder.';

  @override
  String get send => 'Gönder';

  @override
  String get typing => 'yazıyor...';

  @override
  String get attachPhoto => 'Fotoğraf';

  @override
  String get takePhoto => 'Kamera';

  @override
  String get recordVoice => 'Sesli mesaj';

  @override
  String get holdToRecord => 'Kaydediliyor…';

  @override
  String get slideToCancelVoice => 'İptal için sola kaydır';

  @override
  String get releaseToSendVoice => 'Göndermek için bırak';

  @override
  String get holdAgainToRecord => 'Mikrofon hazır — kaydetmek için basılı tut';

  @override
  String get voiceTooShort =>
      'Sesli mesaj göndermek için biraz daha uzun basılı tut.';

  @override
  String get playVoice => 'Oynat';

  @override
  String get pauseVoice => 'Duraklat';

  @override
  String get previewPhoto => 'Bu fotoğraf gönderilsin mi?';

  @override
  String get messageDeleted => 'Mesaj silindi';

  @override
  String get messageDecryptFailed => 'Bu mesaj çözülemedi.';

  @override
  String get chatE2eeTitle => 'Uçtan uca şifreli';

  @override
  String get chatE2eeSubtitle =>
      'Mesajlarınızı yalnızca siz ve bu kişi okuyabilir.';

  @override
  String get deleteMessage => 'Sil';

  @override
  String get deleteMessageConfirm =>
      'Bu mesaj silinsin mi? Karşı taraf artık göremez.';

  @override
  String get micDeniedChat => 'Sesli mesaj için mikrofon izni gerekir.';

  @override
  String get photoDeniedChat => 'Fotoğraf göndermek için galeri izni gerekir.';

  @override
  String get callCancelled => 'Arama iptal edildi';

  @override
  String get callRejected => 'Arama reddedildi';

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
  String get chatEncryptionNotReady =>
      'Uçtan uca şifreleme henüz hazır değil. Karşı tarafın anahtarı yayınlanınca tekrar dene.';

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
  String get presenceTyping => 'yazıyor...';

  @override
  String lastSeenToday(String time) {
    return 'Son görülme bugün $time';
  }

  @override
  String lastSeenYesterday(String time) {
    return 'Son görülme dün $time';
  }

  @override
  String lastSeenOnDate(String date, String time) {
    return 'Son görülme $date $time';
  }

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
  String get hideProfile => 'Profili gizle';

  @override
  String get hideProfileTitle => 'Bu profil gizlensin mi?';

  @override
  String get hideProfileMessage => 'Keşif yığınında bir daha görünmez.';

  @override
  String get linkedAccounts => 'Bağlı hesaplar';

  @override
  String get link => 'Bağla';

  @override
  String get linked => 'Bağlı';

  @override
  String get linkEmailTitle => 'E-posta ve şifre bağla';

  @override
  String get linkEmailSubtitle =>
      'Bu, mevcut hesabına e-posta ile girişi ekler. Başka bir Mevora hesabını birleştirmez.';

  @override
  String get deleteAccount => 'Hesabı sil';

  @override
  String get deleteAccountTitle => 'Hesabın silinsin mi?';

  @override
  String get deleteAccountBody =>
      'Mevora hesabın, profilin, eşleşmelerin ve mesajların kalıcı olarak silinir. Bu işlem geri alınamaz.';

  @override
  String get exportMyData => 'Verilerimi indir';

  @override
  String get exportMyDataTitle => 'Verilerin dışa aktarılsın mı?';

  @override
  String get exportMyDataBody =>
      'Mevora; hesabın, profilin, tercihlerin, eşleşmelerin, beğenilerin, engellemelerin, oluşturduğun raporların ve satın alımların olduğu bir JSON dosyası hazırlar. Tam konum, mesaj içerikleri ve gizli anahtarlar dahil edilmez.';

  @override
  String exportMyDataSuccess(String path) {
    return 'Dışa aktarım kaydedildi: $path';
  }

  @override
  String get exportMyDataFailed =>
      'Verilerin dışa aktarılamadı. Lütfen sonra tekrar dene.';

  @override
  String get settingsShowAge => 'Profilde yaşı göster';

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
  String get boostTitle => 'Smart Boost';

  @override
  String get boostSubtitle =>
      'Daha fazla rastgele kişiye değil — sana uygun daha fazla kişiye görün.';

  @override
  String get boostDuration => 'Profilini öne çıkar';

  @override
  String get boostActivate => 'Kalan bakiyeyi kullan';

  @override
  String get boostBuy => 'Boost satın al';

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
  String get boostAlreadyActive =>
      'Aktif bir Boost\'un var. Yeni paket kalan süreye eklenir.';

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
    return '$minutes dk kaldı';
  }

  @override
  String boostRemainingDays(int days) {
    return '$days gün kaldı';
  }

  @override
  String boostRemainingHours(int hours) {
    return '$hours saat kaldı';
  }

  @override
  String get boostSpotlight => 'Öne Çıkar';

  @override
  String get boostPackOne => '1 Boost';

  @override
  String get boostPackFive => '5 Boost';

  @override
  String get boostPackTen => '10 Boost';

  @override
  String boostPackCount(int count) {
    return '$count Boost';
  }

  @override
  String get boostPackWeek => '1 Hafta';

  @override
  String get boostPackMonth => '1 Ay';

  @override
  String get boostPackYear => '1 Yıl';

  @override
  String get boostPackWeekSubtitle => 'Profilini 7 gün boyunca öne çıkar';

  @override
  String get boostPackMonthSubtitle => 'Profilini 30 gün boyunca öne çıkar';

  @override
  String get boostPackYearSubtitle => 'Profilini 365 gün boyunca öne çıkar';

  @override
  String get boostBestValue => 'En avantajlı';

  @override
  String boostBalance(int count) {
    return '$count kalan Boost';
  }

  @override
  String get boostBuyPack => 'Satın al';

  @override
  String get boostCreditedTitle => 'Boost hesabına eklendi';

  @override
  String boostCreditedMessage(int count) {
    return '$count Boost hesabına tanımlandı. Hazır olduğunda aktif et.';
  }

  @override
  String get boostInsufficientBalance => 'Aktif etmek için Boost bakiyen yok.';

  @override
  String get boostHistoryTitle => 'Satın Alma Geçmişi';

  @override
  String get boostHistoryEmpty => 'Henüz satın alman yok.';

  @override
  String get boostHistoryPurchase => 'Satın alma';

  @override
  String get boostHistoryActivation => 'Aktivasyon';

  @override
  String get boostHistoryPlatformIos => 'App Store';

  @override
  String get boostHistoryPlatformAndroid => 'Google Play';

  @override
  String get boostActiveBadge => 'Boost aktif';

  @override
  String get boostDiscoverBadge => 'ÖNE ÇIKARILDI';

  @override
  String get boostActivating => 'Boost aktif ediliyor...';

  @override
  String get boostNoBalance => 'Profilini öne çıkarmak için bir paket seç.';

  @override
  String get boostPriceUnavailable => 'Fiyat yüklenemedi';

  @override
  String get boostRestoring => 'Satın almalar geri yükleniyor...';

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

  @override
  String get permissionCameraTitle => 'Kamera';

  @override
  String get permissionCameraDescription =>
      'Mevora, profil fotoğrafı çekmek için kameranı kullanır.';

  @override
  String get permissionMicrophoneTitle => 'Mikrofon';

  @override
  String get permissionMicrophoneDescription =>
      'Mevora, ses ve sesli özellikler için mikrofonunu kullanır.';

  @override
  String get permissionPhotosTitle => 'Fotoğraflar';

  @override
  String get permissionPhotosDescription =>
      'Profil fotoğrafı ekleyebilmen için Mevora\'nın fotoğraflarına erişmesi gerekir.';

  @override
  String get permissionLocationTitle => 'Konum';

  @override
  String get permissionLocationDescription =>
      'Mevora, mesafe ve yakındaki keşfi iyileştirmek için konumunu kullanır.';

  @override
  String get permissionNotificationsTitle => 'Bildirimler';

  @override
  String get permissionNotificationsDescription =>
      'Bildirimler, eşleşme veya mesaj aldığında haberin olmasını sağlar.';

  @override
  String get permissionAllow => 'Devam et';

  @override
  String get permissionDeniedTitle => 'İzin gerekli';

  @override
  String get permissionDeniedBody =>
      'Bu özellik izinle daha iyi çalışır. Tekrar deneyebilir veya izinsiz devam edebilirsin.';

  @override
  String get permissionPermanentlyDeniedBody =>
      'İzin kapalı. Cihaz ayarlarından açabilirsin.';

  @override
  String get permissionContinueWithout => 'İzinsiz devam et';

  @override
  String get permissionStatusGranted => 'İzin verildi';

  @override
  String get permissionStatusDenied => 'İzin verilmedi';

  @override
  String get permissionStatusRestricted => 'Kısıtlı';

  @override
  String get permissionStatusLimited => 'Sınırlı erişim';

  @override
  String get permissionStatusPermanentlyDenied =>
      'Kapalı — cihaz ayarlarını aç';

  @override
  String get permissionStatusUnknown => 'Bilinmiyor';

  @override
  String get privacyPermissionsTitle => 'Gizlilik ve izinler';

  @override
  String get privacyPermissionsSubtitle =>
      'Mevora her izni yalnızca ilgili özellik gerektiğinde ister. İsteğe bağlı izinler olmadan da uygulamayı kullanabilirsin.';

  @override
  String get privacyOpenDeviceSettings => 'Cihaz ayarlarını aç';

  @override
  String get selectCityInstead => 'Bunun yerine şehir seç';

  @override
  String get addPhotoCamera => 'Fotoğraf çek';

  @override
  String get addPhotoGallery => 'Galeriden seç';

  @override
  String get photoEmptyHint => 'Devam etmek için ilk fotoğrafını ekle.';

  @override
  String get photoMinRequired => 'En az 3 fotoğraf eklemelisin.';

  @override
  String photoUploadingPercent(int percent) {
    return 'Fotoğraf yükleniyor... %$percent';
  }

  @override
  String get photoUploadFailed =>
      'Fotoğraf yüklenirken bir hata oluştu. Lütfen tekrar deneyin.';

  @override
  String get photoUploaded => 'Fotoğraf yüklendi';

  @override
  String get photoSelected => 'Fotoğraf seçildi';

  @override
  String get photoRetry => 'Tekrar Dene';

  @override
  String get enableDeviceNotifications => 'Bildirimleri aç';

  @override
  String get settingsChangePassword => 'Şifreyi değiştir';

  @override
  String get settingsEmailUnavailable => 'Kayıtlı e-posta yok';

  @override
  String get settingsReadOnly => 'Salt okunur';

  @override
  String get settingsPrivacySafety => 'Gizlilik ve güvenlik';

  @override
  String get settingsPrivacyControls => 'Gizlilik';

  @override
  String get settingsLocation => 'Konum';

  @override
  String get settingsSupport => 'Destek';

  @override
  String get settingsLogoutTitle => 'Çıkış yapılsın mı?';

  @override
  String get settingsLogoutBody =>
      'Mevora\'yı kullanmak için tekrar giriş yapman gerekecek.';

  @override
  String get settingsDeleteConfirmTitle => 'Bu kalıcıdır';

  @override
  String get settingsDeleteConfirmBody =>
      'Tüm eşleşmeler, mesajlar ve profil verilerin kalıcı olarak silinir.';

  @override
  String get settingsReauthTitle => 'Kimliğini doğrula';

  @override
  String get settingsCurrentPasswordRequired => 'Mevcut şifreni gir.';

  @override
  String get settingsNewPasswordRequired => 'Yeni bir şifre gir.';

  @override
  String get settingsConfirmPasswordRequired => 'Yeni şifreni onayla.';

  @override
  String get settingsPasswordsDoNotMatch => 'Şifreler eşleşmiyor.';

  @override
  String get settingsPhotoMinRequired => 'En az 3 profil fotoğrafı bırak.';

  @override
  String get settingsPhotoMaxExceeded => 'En fazla 6 fotoğraf ekleyebilirsin.';

  @override
  String get settingsPhotoPrimaryDeleteBlocked =>
      'Bunu silmeden önce başka bir fotoğrafı birincil yap.';

  @override
  String get settingsPhotoPrimaryRequired => 'Bir birincil fotoğraf seç.';

  @override
  String get settingsFirstNameRequired => 'Ad gerekli.';

  @override
  String get settingsFirstNameTooLong => 'Ad çok uzun.';

  @override
  String get settingsBioTooLong => 'Hakkında metni çok uzun.';

  @override
  String get settingsInterestsTooMany => 'Daha az ilgi alanı seç.';

  @override
  String get settingsMinAgeInvalid => 'Minimum yaş en az 18 olmalı.';

  @override
  String get settingsMaxAgeInvalid => 'Maksimum yaş çok yüksek.';

  @override
  String get settingsAgeRangeInvalid =>
      'Maksimum yaş, minimum yaştan büyük olmalı.';

  @override
  String get settingsDistanceInvalid => 'Mesafe 1 ile 500 km arasında olmalı.';

  @override
  String get settingsGooglePasswordMessage =>
      'Hesabın Google ile giriş kullanıyor. Şifre değişiklikleri Google üzerinden yapılır.';

  @override
  String get settingsBirthDateLocked =>
      'Doğum günü onboarding sonrası değiştirilemez. Yaş yalnızca doğum gününden hesaplanır.';

  @override
  String get settingsSaveProfile => 'Profili kaydet';

  @override
  String get settingsUnblock => 'Engeli kaldır';

  @override
  String get settingsBlockedEmptyTitle => 'Engellenen yok';

  @override
  String get settingsBlockedEmptyMessage =>
      'Engellediğin kişiler burada görünür.';

  @override
  String get settingsShowOnlineStatus => 'Çevrimiçi durumunu göster';

  @override
  String get settingsShowLastSeen => 'Son görülmemi göster';

  @override
  String get settingsShowTypingStatus => 'Yazıyor durumunu göster';

  @override
  String get settingsShowDistance => 'Mesafeyi göster';

  @override
  String get settingsShowActivity => 'Aktivite durumunu göster';

  @override
  String get settingsPushNotifications => 'Anlık bildirimler';

  @override
  String get settingsSuperLikeNotifications => 'Super Like bildirimleri';

  @override
  String get settingsSetPrimaryPhoto => 'Birincil yap';

  @override
  String get settingsDeletePhoto => 'Fotoğrafı kaldır';

  @override
  String get settingsAddPhoto => 'Fotoğraf ekle';

  @override
  String get settingsEducation => 'Eğitim';

  @override
  String get settingsLifestyle => 'Yaşam tarzı';

  @override
  String get settingsInterestedIn => 'İlgilendiğim';

  @override
  String get settingsRelationshipGoal => 'İlişki hedefi';

  @override
  String get settingsCity => 'Şehir';

  @override
  String get settingsGender => 'Cinsiyet';

  @override
  String get settingsNewPassword => 'Yeni şifre';

  @override
  String get settingsCurrentPassword => 'Mevcut şifre';

  @override
  String get settingsConfirmPassword => 'Şifreyi onayla';

  @override
  String get settingsPasswordChanged => 'Şifre güncellendi.';

  @override
  String get settingsProfileSaved => 'Profil kaydedildi.';

  @override
  String get citySelectTitle => 'Şehir Seç';

  @override
  String get citySelectSearch => 'İl ara…';

  @override
  String get citySelectNone => 'İl bulunamadı';

  @override
  String get discoveryLoading => 'Senin için kişiler keşfediliyor...';

  @override
  String get discoveryLoadErrorTitle =>
      'Profilleri yüklerken bir sorun oluştu.';

  @override
  String get discoveryLoadErrorMessage =>
      'Bağlantını kontrol et ve tekrar dene.';

  @override
  String get discoveryChangePreferences => 'Keşfetme tercihlerini değiştir';

  @override
  String get itsAMatchHeadline => 'BİR EŞLEŞMENİZ VAR!';

  @override
  String get demoProfileBadge => 'Örnek';

  @override
  String sharedHobbiesCount(int count) {
    return '$count ortak hobi';
  }

  @override
  String get tabSettings => 'Ayarlar';

  @override
  String get tabMusic => 'Müzik';

  @override
  String get musicTitle => 'Müzik';

  @override
  String get musicConnectCta => '🎵 Spotify\'ı Bağla';

  @override
  String get musicConnected => '✓ Spotify Bağlandı';

  @override
  String get musicUnconnectedCopy =>
      'Spotify hesabını bağla ve müzik zevkine göre sana en uygun kişileri keşfet.';

  @override
  String get musicConnecting => 'Spotify bağlanıyor…';

  @override
  String get musicSyncing => 'Müzik zevkin yenileniyor…';

  @override
  String get musicRefresh => 'Müzik Verilerini Yenile';

  @override
  String get musicRefreshCooldown => 'Daha sonra tekrar yenileyebilirsin.';

  @override
  String get musicProfileTitle => 'Müzik profilin';

  @override
  String get musicSameTasteTitle => 'Seninle Aynı Müziği Dinleyenler';

  @override
  String get musicSameTasteEmpty =>
      'Henüz örtüşen bir müzik zevki yok. Biraz dinledikten sonra yenile.';

  @override
  String get musicWeeklyTitle => 'Bu Haftanın Müzikleri';

  @override
  String get musicWeeklyEmpty =>
      'Yeterince kişi Spotify bağladığında haftalık öne çıkanlar burada görünür.';

  @override
  String musicCompatibilityPercent(int percent) {
    return 'Benzer müzik zevki · en fazla %$percent';
  }

  @override
  String musicCompatibilityShort(int percent) {
    return 'Müzik · %$percent';
  }

  @override
  String musicSharedCounts(int tracks, int artists) {
    return '$tracks ortak parça · $artists ortak sanatçı';
  }

  @override
  String get musicOauthCancelled => 'Spotify bağlantısı iptal edildi.';

  @override
  String get musicApiDenied =>
      'Spotify erişime izin vermedi. Daha sonra tekrar deneyebilirsin.';

  @override
  String get musicTokenExpired =>
      'Spotify bağlantının süresi doldu. Lütfen tekrar bağla.';

  @override
  String get musicNetwork => 'İnternet bağlantını kontrol et ve tekrar dene.';

  @override
  String get musicNotConfigured => 'Spotify bu sürümde henüz yapılandırılmadı.';

  @override
  String get musicConnectError =>
      'Spotify bağlanamadı. Mevora\'nın geri kalanı çalışmaya devam eder.';

  @override
  String get settingsConnectSpotify => 'Spotify\'ı Bağla';

  @override
  String get settingsSpotifySubtitle =>
      'Müzik zevki eşleşmesi — Mevora içinde müzik çalmaz.';

  @override
  String get matchScoreTitle => 'Eşleşme puanı';

  @override
  String get matchScoreSubtitle => 'Bağlantı itibarın';

  @override
  String matchScoreValue(int score) {
    return '$score puan';
  }

  @override
  String get matchScoreHistoryTitle => 'Puan geçmişi';

  @override
  String get matchScoreHistoryEmpty =>
      'Yeni eşleşmeler ve sohbetler burada puan ekler.';

  @override
  String get matchScoreHistoryMatch => 'Yeni eşleşme +1';

  @override
  String get matchScoreHistoryInteraction => 'Sohbet +1';

  @override
  String get matchFeedbackTitle => 'Bu eşleşme nasıldı?';

  @override
  String get matchFeedbackMessage =>
      'İsteğe bağlı. Bu not yalnızca senin geçmişinde kalır — karşı taraf görmez ve puanları değiştirmez.';

  @override
  String get matchFeedbackHint => 'Kısa bir özel not';

  @override
  String get matchFeedbackSubmit => 'Notu kaydet';

  @override
  String get matchFeedbackThanks => 'Geçmişine kaydedildi.';

  @override
  String get matchFeedbackTooShort => 'Kısa bir not yaz veya atla.';

  @override
  String get matchFeedbackFailed => 'Not kaydedilemedi. Tekrar dene.';

  @override
  String get relationshipPromptTitle => 'İlişkiler hakkında ne düşünüyorsun?';

  @override
  String get relationshipQuestionsPreparing =>
      'Yeni sorular hazırlanıyor. Lütfen biraz sonra tekrar deneyin.';

  @override
  String get relationshipTestTitle => 'İlişki Testi';

  @override
  String get relationshipTestHeadline => 'Görüşlerine yakın insanları keşfet';

  @override
  String get relationshipTestMessage =>
      '3 kısa soruyla benzer düşünebilen kişileri gör.';

  @override
  String get relationshipTestStart => 'İlişki Testine Başla';

  @override
  String get relationshipTestLater => 'Daha Sonra';

  @override
  String get relationshipInitialTestTitle => 'İlk Uyumluluk Testin';

  @override
  String get relationshipInitialTestHeadline => 'Uyumluluk profilini oluştur';

  @override
  String get relationshipInitialTestMessage =>
      '3 kısa soruyu bir kez yanıtla. Bundan sonra uyumluluk etkinlikleri her saat Mevora Hour olarak açılır.';

  @override
  String get relationshipInitialTestStart => 'İlk testime başla';

  @override
  String get mevoraHourTitle => 'MEVORA HOUR';

  @override
  String get mevoraHourHeadline => 'Bu saatin Compatibility Challenge\'ı';

  @override
  String get mevoraHourMessage =>
      'Bu saatin Compatibility Challenge\'ına katıl ve benzer cevap verenlerle eşleş.';

  @override
  String get mevoraHourJoin => 'Challenge\'a Katıl';

  @override
  String get mevoraHourJoinNow => 'Şimdi Katıl';

  @override
  String get mevoraHourLiveBadge => 'MEVORA HOUR — CANLI';

  @override
  String mevoraHourLiveTitle(String hour) {
    return '$hour:00 Compatibility Hour başladı';
  }

  @override
  String mevoraHourUpcomingTitle(String hour) {
    return '$hour:00 MEVORA HOUR';
  }

  @override
  String get mevoraHourUpcomingBody =>
      'Bir sonraki Compatibility Hour yaklaşıyor. Bu saatte diğer aktif kullanıcılarla uyumluluğunu keşfet.';

  @override
  String mevoraHourUpcomingCountdown(String countdown) {
    return '$countdown sonra başlıyor';
  }

  @override
  String get mevoraHourJoinedTitle => 'Bu saatin Challenge\'ına katıldın';

  @override
  String get mevoraHourJoinedBody => 'Uyumluluk için soruları yanıtla.';

  @override
  String get mevoraHourAnsweredTitle => 'Cevapların kaydedildi';

  @override
  String get mevoraHourAnsweredBody =>
      'Diğer katılımcıların cevapları bekleniyor. Bu saat tamamlanınca uyumlulukların gösterilecek.';

  @override
  String get mevoraHourResultTitle => 'Bu saatte keşfettiğin uyumluluklar';

  @override
  String get mevoraHourResultBody =>
      'Bu Mevora Hour\'da benzer cevap veren kişiler.';

  @override
  String mevoraHourEndedTitle(String hour) {
    return '$hour:00 Mevora Hour sona erdi';
  }

  @override
  String mevoraHourEndedBody(String hour) {
    return 'Bir sonraki Compatibility Hour: $hour:00';
  }

  @override
  String get mevoraHourRemindMe => 'Bana Hatırlat';

  @override
  String get mevoraHourReminderOn => 'Hatırlatıcı açık';

  @override
  String get mevoraHourReminderSaved =>
      'Mevora Hour başlayınca seni bilgilendireceğiz.';

  @override
  String get mevoraHourReminderNeedPermission =>
      'Mevora Hour hatırlatması için bildirim izni gerekli.';

  @override
  String get mevoraHourReminderNeedSignIn => 'Hatırlatıcı için giriş yap.';

  @override
  String get mevoraHourRemindersSetting => 'Mevora Hour hatırlatıcıları';

  @override
  String get mevoraHourRemindersSettingSubtitle =>
      'Her Compatibility Hour açılınca isteğe bağlı bildirim (Europe/Istanbul).';

  @override
  String mevoraHourCountdown(String countdown) {
    return '$countdown kaldı';
  }

  @override
  String mevoraHourRoundLabel(String hour) {
    return '$hour:00 Mevora Hour';
  }

  @override
  String get mevoraHourUnavailableTitle => 'Sonraki Compatibility Hour yakında';

  @override
  String get mevoraHourUnavailableMessage =>
      'Şu an açık bir Mevora Hour yok. Bir sonraki saat başında tekrar bak (Europe/Istanbul).';

  @override
  String matchingGameCountdown(String countdown) {
    return 'Sonraki Eşleşme Oyunu: $countdown';
  }

  @override
  String matchingGameRoundLabel(String hour) {
    return '$hour:00 Eşleşme Oyunu';
  }

  @override
  String get matchingGameWaitingTitle => 'Eşleşme hesaplanıyor';

  @override
  String get matchingGameWaitingMessage =>
      'Cevapların kaydedildi. Bu saatin turu tamamlanınca eşleşmen gösterilecek.';

  @override
  String get matchingGameWaitingDismiss => 'Tamam';

  @override
  String get relationshipContinueTitle => 'Eşleşmeye devam etmek ister misin?';

  @override
  String get relationshipContinueMessage =>
      '5 eşleşme turunu tamamladın. Aynı cevaplara sahip insanları bulmaya devam etmek ister misin?';

  @override
  String get relationshipContinueYes => 'Devam Et';

  @override
  String get relationshipContinueNo => 'Şimdi Değil';

  @override
  String get likesYouTitle => 'Sizi Beğendi';

  @override
  String get likesYouEntrySubtitle => 'Profilini beğenenleri gör';

  @override
  String get likesYouLockedTitle => 'Biri seni beğendi';

  @override
  String likesYouLockedCount(int count) {
    return '$count kişi seni beğendi';
  }

  @override
  String get likesYouLockedMessage =>
      'Seni kimin beğendiğini görmek için Premium\'a geç. İsimler ve fotoğraflar o zamana kadar gizli kalır.';

  @override
  String get likesYouUnlockCta => 'Premium ile aç';

  @override
  String get likesYouBlurredHint => 'Seni beğenenler';

  @override
  String get likesYouHiddenName => 'Özel biri';

  @override
  String get likesYouHiddenSubtitle => 'Profilini görmek için kilidi aç';

  @override
  String get likesYouEmptyTitle => 'Henüz yeni beğeni yok';

  @override
  String get likesYouEmptyMessage => 'Biri seni beğendiğinde burada görünür.';

  @override
  String get likesYouLoadError => 'Beğeniler yüklenemedi. Lütfen tekrar dene.';

  @override
  String get relationshipTestDoneTitle => 'İlişki Testin Tamamlandı';

  @override
  String get relationshipTestFound => 'Görüşlerine yakın biri bulundu.';

  @override
  String get relationshipTestAlign => 'Birkaç konuda benzer görüşleriniz var.';

  @override
  String get relationshipTestNearest => 'Size en yakın kişi:';

  @override
  String get relationshipTestEmpty =>
      'Şu an yakınında benzer düşünen kimse yok.';

  @override
  String get relationshipTestViewProfile => 'Profili Gör';

  @override
  String get relationshipTestOpenChat => 'Sohbete git';

  @override
  String get relationshipMatchBadge => 'İlişki Testi';

  @override
  String relationshipPromptProgress(int answered, int total) {
    return '$answered / $total';
  }

  @override
  String relationshipCompatibilityPercent(int percent) {
    return 'Görüş örtüşmesi · %$percent';
  }

  @override
  String relationshipCompatibilityShort(int percent) {
    return 'Görüş · %$percent';
  }

  @override
  String relationshipSharedViews(int count) {
    return '$count ortak görüş';
  }

  @override
  String get relationshipSimilarThinker =>
      'Seninle ilişki konusunda benzer düşünen biri bulundu.';

  @override
  String get relationshipViewsAlign =>
      'İlişki görüşleriniz birkaç konuda örtüşüyor.';

  @override
  String get relationshipMatchesTitle => 'İlişki eşleşmeleri';

  @override
  String get relationshipMatchesEmpty =>
      'Senin gibi düşünen insanları bulmak için birkaç ilişki sorusu yanıtla — burada mesafe önemli değil.';

  @override
  String relationshipProfileSubtitle(int answered) {
    return '$answered ilişki sorusu yanıtlandı';
  }

  @override
  String get relationshipTopicJealousy =>
      'Kıskançlık konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicTrust => 'Güven konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicLoyalty =>
      'Sadakat konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicCommunication =>
      'İletişim konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicBoundaries =>
      'Sınırlar konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicSocialLife =>
      'Sosyal hayat konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicFriendship =>
      'Arkadaşlık konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicPersonalSpace =>
      'Özel alan konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicFuturePlans =>
      'Gelecek planları konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicMoney => 'Para konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicFlirting =>
      'Flört konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicExes =>
      'Eski ilişkiler konusunda benzer düşünüyorsunuz.';

  @override
  String get relationshipTopicExpectations =>
      'İlişki beklentileri konusunda benzer düşünüyorsunuz.';

  @override
  String get verifyYourProfile => 'Profilini doğrula';

  @override
  String get verificationDescription =>
      'Doğrulama, Mevora\'yı daha güvenli ve gerçek kullanıcılarla dolu tutmamıza yardımcı olur.';

  @override
  String get verificationBenefitFakeProfiles =>
      'Sahte profillere karşı koruma sağlar';

  @override
  String get verificationBenefitSpoofing =>
      'Sahteciliği önlemeye yardımcı olur';

  @override
  String get verificationBenefitBadge => 'Profiline doğrulanmış rozet ekler';

  @override
  String get startVerification => 'Doğrulamayı başlat';

  @override
  String get verificationInProgress => 'Doğrulama devam ediyor';

  @override
  String get profileVerified => 'Profil doğrulandı';

  @override
  String get profileVerifiedBadge => 'Doğrulandı';

  @override
  String get verificationCouldNotComplete => 'Doğrulama tamamlanamadı';

  @override
  String get tryVerificationAgain => 'Tekrar dene';

  @override
  String get verificationStarted => 'Doğrulama başlatıldı';

  @override
  String get verificationPrivacyNote =>
      'Doğrulamanız güvenli bir doğrulama sağlayıcısı tarafından işlenir.';

  @override
  String get followVerificationInstructions =>
      'Kendinizi doğrulamak için talimatları izleyin.';

  @override
  String get verificationNotConfigured =>
      'Doğrulama geçici olarak kullanılamıyor.';

  @override
  String get verificationCooldown =>
      'Tekrar denemeden önce birkaç dakika bekleyin.';

  @override
  String get verificationAttemptLimit =>
      'Bugünkü doğrulama limitine ulaştınız. Yarın tekrar deneyin.';

  @override
  String get whyYouMatch => 'Neden eşleşiyorsunuz?';

  @override
  String get compatWhyButton => 'Neden?';

  @override
  String compatDiscoverBadge(int percent) {
    return '%$percent Uyumlu';
  }

  @override
  String get compatCalculating => 'Hesaplanıyor...';

  @override
  String get compatUnavailable => 'Uyumluluk hesaplanamadı';

  @override
  String get profileEditSectionPhotos => 'Fotoğraflar';

  @override
  String get profileEditSectionBasic => 'Temel bilgiler';

  @override
  String get profileEditSectionAbout => 'Hakkında';

  @override
  String get profileEditSectionInterests => 'İlgi alanların';

  @override
  String get profileEditSectionLifestyle => 'Yaşam tarzı';

  @override
  String get profileEditSectionRelationship => 'İlişki tercihleri';

  @override
  String get profileEditSectionAnswers => 'Cevapların';

  @override
  String get profileEditDiscoveryPrefs => 'Yaş aralığı ve mesafe';

  @override
  String get profileEditAnswersSubtitle =>
      'İlişki sorularına verdiğin cevapları güncelle';

  @override
  String get saveChanges => 'Değişiklikleri kaydet';

  @override
  String get discardChangesTitle =>
      'Değişiklikleri kaydetmeden çıkmak istiyor musun?';

  @override
  String get discardChangesMessage => 'Profil değişikliklerin kaydedilmedi.';

  @override
  String get keepEditing => 'Düzenlemeye devam et';

  @override
  String get discard => 'Vazgeç';

  @override
  String get interestsMinRequired => 'En az 3 ilgi alanı seç';

  @override
  String get profileAnswersTitle => 'Cevapların';

  @override
  String get profileAnswersEmpty => 'Henüz ilişki sorusu cevaplamadın.';

  @override
  String get profileAnswersEdit => 'Düzenle';

  @override
  String get questionAnswersTitle => 'Soru & Cevap';

  @override
  String get questionAnswersEmpty => 'Henüz cevapladığın bir soru yok.';

  @override
  String get questionAnswersEmptyHint =>
      'Profilini daha kişisel hale getirmek için birkaç ilişki sorusu cevapla. İstediğin zaman düzenleyebilirsin.';

  @override
  String get questionAnswersSaveError =>
      'Cevabın kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String seeAllAnswers(int count) {
    return '$count cevabı daha gör';
  }

  @override
  String get showOnProfile => 'Profilimde göster';

  @override
  String get questionAnswersLoadError =>
      'Cevaplar yüklenirken bir sorun oluştu.';

  @override
  String get questionAnswersMatchRequired =>
      'Bu kişinin cevaplarını görmek için eşleşmeniz gerekiyor.';

  @override
  String get questionAnswersMatchedSubtitle => 'Ortak yönlerinizi keşfedin.';

  @override
  String get questionAnswersPremiumRequired =>
      'Cevaplarını görmek için Premium\'a geç.';

  @override
  String get questionAnswersPremiumLockedAnswer =>
      'Cevabını görmek için Premium\'a geç';

  @override
  String get questionAnswersPeerEmpty =>
      'Bu kişi henüz profilinde soru cevabı paylaşmamış.';

  @override
  String get matchViewAnswers => 'Cevapları gör';

  @override
  String get chatDiscoverAnswersPrompt => 'Onu biraz daha tanı';

  @override
  String compatOverallLabel(int percent) {
    return 'Uyumluluğunuz %$percent';
  }

  @override
  String get compatNotEnoughData => 'Henüz yeterli veri yok';

  @override
  String get compatStrongestConnection => 'En güçlü bağ';

  @override
  String get compatPotentialDifference => 'Potansiyel fark';

  @override
  String get compatCategoryOverall => 'Genel';

  @override
  String get compatCategoryRelationship => 'İlişki';

  @override
  String get compatCategoryInterests => 'İlgi alanları';

  @override
  String get compatCategoryLifestyle => 'Yaşam tarzı';

  @override
  String get compatCategoryQuestions => 'Sorular';

  @override
  String get compatCategoryMusic => 'Müzik';

  @override
  String get compatCategoryCommunication => 'İletişim';

  @override
  String get compatCategoryProximity => 'Yakınlık';

  @override
  String get compatCategoryActivity => 'Aktivite';

  @override
  String compatReasonSameRelationshipGoal(String goal) {
    return 'İkiniz de $goal ilişki istiyorsunuz';
  }

  @override
  String compatReasonSharedInterests(String interests) {
    return 'İkiniz de $interests seviyorsunuz';
  }

  @override
  String get compatReasonSimilarLifestyle => 'Benzer bir yaşam tarzınız var';

  @override
  String compatReasonSameAnswers(String aligned, String shared) {
    return '$shared sorunun $aligned tanesine aynı cevabı verdiniz';
  }

  @override
  String compatReasonSimilarMusic(String score) {
    return 'Müzik zevkiniz %$score uyumlu';
  }

  @override
  String get compatReasonCommunication => 'Benzer iletişim tarzlarınız var';

  @override
  String get hiddenCompatTitle => 'Biri senin gibi düşünüyor 👀';

  @override
  String hiddenCompatMessage(int count) {
    return 'Biri seninle aynı şekilde $count soruya cevap verdi.';
  }

  @override
  String hiddenCompatCompatibility(int percent) {
    return '%$percent uyumluluk';
  }

  @override
  String get hiddenCompatCta => 'Uyumluluğunu keşfet';

  @override
  String get hiddenCompatDismiss => 'Şimdi değil';

  @override
  String get supportCenterTitle => 'Yardım ve Destek';

  @override
  String get supportCenterSubtitle =>
      'Yanıtları bulun, politikaları inceleyin veya ekibimize ulaşın.';

  @override
  String get supportHelpSection => 'Yardım';

  @override
  String get supportTopicsSection => 'Konular';

  @override
  String get supportFaqTitle => 'Sık Sorulan Sorular';

  @override
  String get supportFaqSubtitle => 'Sık sorulan sorulara hızlı yanıtlar';

  @override
  String get supportFaqSearchHint => 'Soru ara';

  @override
  String get supportFaqEmpty => 'Aramanızla eşleşen soru bulunamadı.';

  @override
  String get supportCreateTicket => 'Destek Talebi Oluştur';

  @override
  String get supportCreateTicketSubtitle =>
      'Sorununuzu açıklayın ve isteğe bağlı ekran görüntüsü ekleyin';

  @override
  String get supportMyTickets => 'Destek Taleplerim';

  @override
  String get supportTicketsEmptyTitle => 'Henüz destek talebi yok';

  @override
  String get supportTicketsEmptyMessage =>
      'Destek ekibine yazdığınızda talepleriniz burada görünür.';

  @override
  String get supportTicketCategory => 'Kategori';

  @override
  String get supportTicketSubject => 'Konu';

  @override
  String get supportTicketMessage => 'Mesaj';

  @override
  String get supportTicketAddScreenshot =>
      'Ekran görüntüsü ekle (isteğe bağlı)';

  @override
  String get supportTicketScreenshotAttached => 'Ekran görüntüsü eklendi';

  @override
  String get supportTicketSubmit => 'Gönder';

  @override
  String get supportTicketSubmitted => 'Destek talebiniz gönderildi.';

  @override
  String get supportTicketFailed => 'Talep gönderilemedi. Tekrar deneyin.';

  @override
  String get supportTicketValidation => 'Konu ve mesaj zorunludur.';

  @override
  String get supportTicketDetailTitle => 'Destek talebi';

  @override
  String get supportTicketStatusLabel => 'Durum';

  @override
  String get supportTicketAttachments => 'Ekler';

  @override
  String get supportTicketStatusOpen => 'Açık';

  @override
  String get supportTicketStatusInProgress => 'İşleniyor';

  @override
  String get supportTicketStatusResolved => 'Çözüldü';

  @override
  String get supportTicketStatusClosed => 'Kapatıldı';

  @override
  String get supportCategoryAccount => 'Hesap ve profil';

  @override
  String get supportCategoryMatches => 'Eşleşmeler';

  @override
  String get supportCategoryMessaging => 'Mesajlaşma';

  @override
  String get supportCategoryPhotos => 'Fotoğraf ve profil';

  @override
  String get supportCategorySafety => 'Bildirme ve engelleme';

  @override
  String get supportCategoryTechnical => 'Teknik sorunlar';

  @override
  String get supportCategoryOther => 'Diğer';

  @override
  String get faqDeleteAccountQ => 'Hesabımı nasıl silebilirim?';

  @override
  String get faqDeleteAccountA =>
      'Ayarlar → Hesap → Hesabı Sil yolunu izleyin. Onayladığınızda Mevora hesabınız ve ilişkili verileriniz kalıcı olarak silinir. Bu işlem geri alınamaz.';

  @override
  String get faqChangePhotoQ => 'Profil fotoğrafımı nasıl değiştiririm?';

  @override
  String get faqChangePhotoA =>
      'Ayarlar → Profili Düzenle\'ye gidin. Galeriden veya kameradan fotoğraf ekleyebilir, kaldırabilir veya değiştirebilirsiniz. Fotoğraflar yayınlanmadan önce incelenebilir.';

  @override
  String get faqCloseAccountQ => 'Hesabımı nasıl kapatırım?';

  @override
  String get faqCloseAccountA =>
      'Hesap kapatma, hesap silme ile aynıdır. Ayarlar → Hesap → Hesabı Sil\'i kullanın. Yalnızca çıkış yapmak verilerinizi silmez.';

  @override
  String get faqHowMatchQ => 'Nasıl eşleşme yapılıyor?';

  @override
  String get faqHowMatchA =>
      'Keşfet\'te iki kullanıcı birbirini beğendiğinde karşılıklı eşleşme oluşur. Eşleşmeler sekmesinden mesajlaşabilirsiniz.';

  @override
  String get faqMatchPercentQ => 'Eşleşme yüzdesi ne anlama geliyor?';

  @override
  String get faqMatchPercentA =>
      'Profil cevapları, ilgi alanları, yaşam tarzı, müzik zevki ve diğer sinyallere dayalı bir uyumluluk tahminidir. Bağ kurma olasılığını anlamanıza yardımcı olur; garanti değildir.';

  @override
  String get faqCantMessageQ => 'Mesaj gönderemiyorsam ne yapmalıyım?';

  @override
  String get faqCantMessageA =>
      'Mesajlaşma yalnızca aktif karşılıklı eşleşmelerde kullanılabilir. Eşleşme sona erdiyse, engellendiyseniz veya sohbet kapandıysa mesaj gönderemezsiniz.';

  @override
  String get faqNotificationsQ => 'Bildirimleri nasıl yönetebilirim?';

  @override
  String get faqNotificationsA =>
      'Ayarlar → Bildirimler\'den eşleşme, mesaj ve diğer uyarıları yönetin. Cihaz ayarlarından da bildirim izni vermeniz gerekebilir.';

  @override
  String get faqBlockQ => 'Bir kullanıcıyı nasıl engellerim?';

  @override
  String get faqBlockA =>
      'Sohbette Daha Fazla → Engelle. Profilde güvenlik menüsünden Engelle\'yi seçin. Engellenen kullanıcılar size mesaj gönderemez ve eşleşmelerinizde görünmez.';

  @override
  String get faqReportQ => 'Bir kullanıcıyı nasıl şikayet ederim?';

  @override
  String get faqReportA =>
      'Profil veya sohbet güvenlik menüsünden Şikayet Et\'i seçin, neden belirtin ve isteğe bağlı açıklama ekleyin. Şikayetler ekibimiz tarafından incelenir.';

  @override
  String get faqStaySafeQ => 'Uygulamada güvenliğimi nasıl koruyabilirim?';

  @override
  String get faqStaySafeA =>
      'Kalabalık yerlerde buluşun, güvenene kadar kişisel bilgilerinizi paylaşmayın, engelle ve şikayet araçlarını kullanın, Topluluk Kuralları\'nı okuyun.';

  @override
  String get guidelinesIntro =>
      'Mevora saygılı bağlantılar için tasarlandı. Bu kurallar profil, mesaj, arama ve tüm uygulama içi davranışlar için geçerlidir.';

  @override
  String get guidelinesRespectTitle => 'Saygılı iletişim';

  @override
  String get guidelinesRespectBody =>
      'Başkalarına saygılı davranın. Anlaşmazlık hakaret, zorbalık veya aşağılayıcı dil için mazeret değildir.';

  @override
  String get guidelinesHarassmentTitle => 'Taciz ve zorbalık yasağı';

  @override
  String get guidelinesHarassmentBody =>
      'Tekrarlayan istenmeyen iletişim, gözdağı, takip veya baskı yasaktır.';

  @override
  String get guidelinesHateTitle => 'Nefret söylemi yasağı';

  @override
  String get guidelinesHateBody =>
      'Korunan özelliklere dayalı saldırılar yasaktır.';

  @override
  String get guidelinesThreatsTitle => 'Tehdit ve şiddet';

  @override
  String get guidelinesThreatsBody =>
      'Tehditler, şiddeti yüceltme veya kendine zarar vermeyi teşvik etme yasaktır.';

  @override
  String get guidelinesSpamTitle => 'Spam';

  @override
  String get guidelinesSpamBody =>
      'İstenmeyen reklam, tekrarlayan mesajlar veya otomatik talep yasaktır.';

  @override
  String get guidelinesFakeTitle => 'Sahte hesaplar';

  @override
  String get guidelinesFakeBody =>
      'Kimlik taklidi, yanıltıcı profil veya gerçek olmayan hesaplar yasaktır.';

  @override
  String get guidelinesScamTitle => 'Dolandırıcılık';

  @override
  String get guidelinesScamBody =>
      'Dolandırıcılık, para talebi veya hassas finansal bilgi isteme yasaktır.';

  @override
  String get guidelinesInappropriateTitle => 'Uygunsuz içerik';

  @override
  String get guidelinesInappropriateBody =>
      'Rahatsız edici, grafik veya uygunsuz içerik profilde veya mesajlarda yasaktır.';

  @override
  String get guidelinesSexualTitle => 'Cinsel içerik ve istismar';

  @override
  String get guidelinesSexualBody =>
      'Rızaya aykırı cinsel içerik, istismar veya reşit olmayanlara yönelik içerik kesinlikle yasaktır ve yetkililere bildirilir.';

  @override
  String get guidelinesMinorsTitle => 'Reşit olmayanların korunması';

  @override
  String get guidelinesMinorsBody =>
      'Mevora 18 yaş ve üzeri içindir. Reşit olmayanlara yönelik hesap veya davranışlar yasaktır.';

  @override
  String get guidelinesPrivacyTitle => 'Kişisel bilgilerin paylaşılması';

  @override
  String get guidelinesPrivacyBody =>
      'Başka birinin izni olmadan özel iletişim bilgilerini, adresini veya belgelerini paylaşmayın.';

  @override
  String get guidelinesMisuseTitle => 'Platformun kötüye kullanılması';

  @override
  String get guidelinesMisuseBody =>
      'Güvenlik sistemlerini aşmaya çalışmak, veri kazımak veya yetkisiz ticari kullanım yasaktır.';

  @override
  String get guidelinesReportTitle => 'Kullanıcıların nasıl raporlanacağı';

  @override
  String get guidelinesReportBody =>
      'Profil veya sohbetten Şikayet Et\'i kullanın. Ayarlardan da destek talebi oluşturabilirsiniz.';

  @override
  String get guidelinesEnforcementTitle => 'Yaptırımlar';

  @override
  String get guidelinesEnforcementBody =>
      'İhlaller uyarı, kısıtlama, askıya alma veya kalıcı kaldırma ile sonuçlanabilir. Ciddi ihlaller yetkililere bildirilebilir.';

  @override
  String get termsIntro =>
      'Bu Kullanım Koşulları, Mevora mobil uygulamasını ve ilgili hizmetleri kullanımınızı düzenler.';

  @override
  String get termsScopeTitle => 'Hizmetin kapsamı';

  @override
  String get termsScopeBody =>
      'Mevora, yetişkinlerin uyumlu kişileri keşfetmesine, karşılıklı beğeniyle eşleşmesine, mesajlaşmasına ve Boost ile doğrulama gibi isteğe bağlı özellikleri kullanmasına yardımcı olur.';

  @override
  String get termsAccountTitle => 'Kullanıcı hesabı';

  @override
  String get termsAccountBody =>
      'En az 18 yaşında olmalısınız. Giriş bilgilerinizin güvenliğinden ve hesabınızdaki faaliyetlerden siz sorumlusunuz.';

  @override
  String get termsResponsibilitiesTitle => 'Kullanıcı sorumlulukları';

  @override
  String get termsResponsibilitiesBody =>
      'Doğru bilgi vermeyi, yasalara uymayı ve Mevora\'yı saygılı ve güvenli kullanmayı kabul edersiniz.';

  @override
  String get termsContentTitle => 'Profil ve içerik sorumluluğu';

  @override
  String get termsContentBody =>
      'Gönderdiğiniz içeriğin sahibi sizsiniz; ancak hizmeti sunmak, moderasyon ve güvenlik için Mevora\'ya barındırma ve işleme lisansı verirsiniz.';

  @override
  String get termsProhibitedTitle => 'Yasaklanan davranışlar';

  @override
  String get termsProhibitedBody =>
      'Taciz, nefret söylemi, dolandırıcılık, sahte profil, cinsel istismar, spam ve platforma zarar verme yasaktır.';

  @override
  String get termsMatchingTitle => 'Eşleşme ve mesajlaşma sistemi';

  @override
  String get termsMatchingBody =>
      'Eşleşmeler karşılıklı beğeniyle oluşur. Mesajlaşma yalnızca aktif eşleşmelerde kullanılabilir ve güvenlik veya engelleme nedeniyle kısıtlanabilir.';

  @override
  String get termsSafetyTitle => 'Kullanıcı güvenliği';

  @override
  String get termsSafetyBody =>
      'Kullanıcıları engelleyebilir ve şikayet edebilirsiniz. Şikayetleri inceleyebilir ve topluluğu korumak için işlem uygulayabiliriz.';

  @override
  String get termsSuspensionTitle =>
      'Hesabın askıya alınması veya sonlandırılması';

  @override
  String get termsSuspensionBody =>
      'Bu Koşulları ihlal eden veya başkaları için risk oluşturan hesapları askıya alabilir veya sonlandırabiliriz.';

  @override
  String get termsDeletionTitle => 'Kullanıcı tarafından hesap silme';

  @override
  String get termsDeletionBody =>
      'Ayarlar → Hesap → Hesabı Sil ile hesabınızı kalıcı olarak silebilirsiniz. Silme geri alınamaz ve yasal saklama sınırları dışında verilerinizi kaldırır.';

  @override
  String get termsPaidTitle => 'Ücretli özellikler / Boost';

  @override
  String get termsPaidBody =>
      'Boost ve diğer satın alımlar uygulama mağazası üzerinden işlenir. İadeler mağaza politikalarına tabidir.';

  @override
  String get termsThirdPartyTitle => 'Üçüncü taraf hizmetler';

  @override
  String get termsThirdPartyBody =>
      'Mevora; Google, Apple, Spotify, Firebase ve doğrulama sağlayıcıları gibi hizmetlerle entegre olabilir. Bu hizmetlerin koşulları da geçerlidir.';

  @override
  String get termsAvailabilityTitle => 'Hizmetin kullanılabilirliği';

  @override
  String get termsAvailabilityBody =>
      'Güvenilir hizmet için çalışırız ancak kesintisiz erişim garanti etmeyiz. Özellikler değişebilir veya kaldırılabilir.';

  @override
  String get termsLiabilityTitle => 'Sorumluluk sınırlamaları';

  @override
  String get termsLiabilityBody =>
      'Yasaların izin verdiği ölçüde Mevora olduğu gibi sunulur. Kullanıcı davranışları veya çevrimdışı etkileşimlerden sorumlu değiliz.';

  @override
  String get termsChangesTitle => 'Koşulların değiştirilmesi';

  @override
  String get termsChangesBody =>
      'Bu Koşulları güncelleyebiliriz. Önemli değişiklikler uygulama veya politika sayfalarında duyurulur.';

  @override
  String get termsContactTitle => 'İletişim';

  @override
  String get termsContactBody =>
      'Hukuki sorular için Ayarlar\'dan destek talebi oluşturun veya halilmertdeveliii@gmail.com adresine yazın.';

  @override
  String get termsEffectiveTitle => 'Yürürlük tarihi';

  @override
  String get termsEffectiveBody =>
      'Bu Koşullar 23 Ağustos 2026 tarihinden itibaren geçerlidir.';

  @override
  String get privacyIntroTitle => 'Giriş';

  @override
  String get privacyIntroBody =>
      'Bu Gizlilik Politikası, Mevora\'yı kullandığınızda kişisel verilerin nasıl toplandığını, kullanıldığını, saklandığını ve silindiğini açıklar.';

  @override
  String get privacyDataCollectedTitle => 'Genel bakış';

  @override
  String get privacyDataCollectedBody =>
      'Yalnızca eşleşme, mesajlaşma, güvenlik, isteğe bağlı müzik özellikleri ve hesap yönetimi için gerekli verileri toplarız.';

  @override
  String get privacyAuthTitle => 'Hesap ve kimlik doğrulama';

  @override
  String get privacyAuthBody =>
      'Giriş yönteminize göre e-posta, telefon numarası, sağlayıcı kimlikleri (Google, Apple, Spotify) ve Firebase Authentication kullanıcı kimliği işlenebilir.';

  @override
  String get privacyProfileTitle => 'Profil ve fotoğraflar';

  @override
  String get privacyProfileBody =>
      'Sağladığınız profil bilgileri ve fotoğraflar Firebase Firestore ve Storage\'da profilinizi göstermek ve eşleşmeyi sağlamak için saklanır.';

  @override
  String get privacyLocationTitle => 'Konum bilgisi';

  @override
  String get privacyLocationBody =>
      'İzninizle yaklaşık konum, yakındaki uyumlu kişileri göstermek için kullanılır. Keşfet sonuçlarında tam koordinatlar diğer kullanıcılara açıklanmaz.';

  @override
  String get privacyMessagingTitle => 'Mesajlar ve aramalar';

  @override
  String get privacyMessagingBody =>
      'Sohbet mesajları, sesli notlar, görseller, yazıyor göstergesi ve arama meta verileri hizmeti sunmak için saklanır. Her iki taraf anahtar yayınladığında mesajlar uçtan uca şifrelenebilir.';

  @override
  String get privacyMatchingTitle => 'Eşleşme bilgileri';

  @override
  String get privacyMatchingBody =>
      'Beğeniler, geçmeler, eşleşmeler, uyumluluk sinyalleri ve etkileşim geçmişi keşfet ve eşleşmeler için saklanır.';

  @override
  String get privacyPreferencesTitle => 'Kullanıcı tercihleri';

  @override
  String get privacyPreferencesBody =>
      'Bildirim tercihleri, gizlilik kontrolleri (çevrimiçi, son görülme, yazıyor), keşfet filtreleri ve dil ayarları tercihlerinize uyulması için saklanır.';

  @override
  String get privacySpotifyTitle => 'Spotify entegrasyonu';

  @override
  String get privacySpotifyBody =>
      'Spotify bağlarsanız, uyumluluk ve müzik özellikleri için hesap meta verileri ve müzik zevki sinyalleri saklanır. Ayarlardan bağlantıyı kesebilirsiniz.';

  @override
  String get privacyDeviceTitle => 'Cihaz ve teknik bilgiler';

  @override
  String get privacyDeviceBody =>
      'Push bildirimleri, tanılama ve güvenlik kayıtları için cihaz belirteçleri Firebase altyapısı üzerinden işlenir.';

  @override
  String get privacyWhyTitle => 'Neden toplanıyor?';

  @override
  String get privacyWhyBody =>
      'Kimliğinizi doğrulamak, eşleşmeleri göstermek, mesajları iletmek, güvenliği artırmak, destek sunmak, satın alımları işlemek ve yasal yükümlülüklere uymak için.';

  @override
  String get privacyStorageTitle => 'Nerede saklanıyor?';

  @override
  String get privacyStorageBody =>
      'Veriler öncelikle Google Firebase\'de (Firestore, Storage, Authentication, Cloud Functions) yapılandırıldığı şekilde AB bölgesinde saklanır.';

  @override
  String get privacyRetentionTitle => 'Ne kadar süre saklanıyor?';

  @override
  String get privacyRetentionBody =>
      'Hesabınız aktifken veriler saklanır. Hesabı sildiğinizde, yasa veya dolandırıcılık önleme gerektirmedikçe ilişkili veriler silinir veya anonimleştirilir.';

  @override
  String get privacySharingTitle => 'Kimlerle paylaşılabiliyor?';

  @override
  String get privacySharingBody =>
      'Kişisel verileri satmayız. Firebase, uygulama mağazaları, Spotify ve doğrulama sağlayıcılarıyla yalnızca hizmeti sunmak için paylaşırız.';

  @override
  String get privacyRightsTitle => 'Haklarınız';

  @override
  String get privacyRightsBody =>
      'Bölgenize göre erişim, düzeltme, silme veya kısıtlama talep edebilirsiniz. Hesap silme Ayarlar\'da mevcuttur.';

  @override
  String get privacyDeletionTitle => 'Verilerinizi silme';

  @override
  String get privacyDeletionBody =>
      'Kalıcı silme için Ayarlar → Hesap → Hesabı Sil\'i kullanın. Oluşturduğunuz destek talepleri de hesap silme sırasında kaldırılır.';

  @override
  String get privacySecurityTitle => 'Güvenlik';

  @override
  String get privacySecurityBody =>
      'Erişim kontrolleri, aktarım şifrelemesi, isteğe bağlı mesaj şifrelemesi ve Firebase güvenlik kuralları kullanıyoruz. Sorunları destek üzerinden bildirin.';

  @override
  String get privacyChildrenTitle => 'Çocuklar';

  @override
  String get privacyChildrenBody =>
      'Mevora 18 yaş altı kullanıcılar içindir. Reşit olmayan hesaplar silinir.';

  @override
  String get privacyChangesTitle => 'Politika değişiklikleri';

  @override
  String get privacyChangesBody =>
      'Bu politikayı güncelleyebiliriz. Güncel sürüm uygulamada ve kamuya açık politika sayfasında yer alır.';

  @override
  String get privacyContactTitle => 'İletişim';

  @override
  String get privacyContactBody =>
      'Gizlilik soruları: halilmertdeveliii@gmail.com veya Ayarlar\'dan destek talebi oluşturun.';

  @override
  String musicMatchTitle(int percent) {
    return '🎵 Müzik Eşleşmesi — %$percent';
  }

  @override
  String get musicInsightBandHigh => 'Müzik zevkiniz oldukça benzer.';

  @override
  String get musicInsightBandMid => 'Bazı güçlü ortak müzik zevkleriniz var.';

  @override
  String get musicInsightBandLow =>
      'Müzik zevkleriniz farklı olsa da birkaç ortak sanatçınız var.';

  @override
  String musicInsightSharedTracks(int count) {
    return '🎵 $count ortak şarkınız var.';
  }

  @override
  String musicInsightSharedArtists(int count) {
    return '🎤 $count ortak sanatçınız var.';
  }

  @override
  String musicInsightSharedPlaylistTracks(int count) {
    return '🎧 Playlistlerinizde $count ortak şarkı var.';
  }

  @override
  String musicInsightSharedRecentTracks(int count) {
    return '🎵 Son dönemde $count aynı şarkıyı dinlemişsiniz.';
  }

  @override
  String musicInsightTopSharedArtist(String name) {
    return '🎵 İkiniz de $name\'i sık dinliyorsunuz.';
  }

  @override
  String musicInsightTopSharedGenres(String genres) {
    return '🎶 Müzik zevkinizin büyük kısmı $genres türlerinde kesişiyor.';
  }

  @override
  String get musicInsightDataUnavailable =>
      'Karşılaştırma için henüz yeterli Spotify verisi yok.';

  @override
  String get musicSpotifyNotConnected => 'Spotify bağlı değil';

  @override
  String get musicSharedTracksHeading => '🎵 Ortak şarkılarınız';

  @override
  String get musicSharedArtistsHeading => '🎤 Ortak sanatçılarınız';

  @override
  String get musicSharedGenresHeading => '🎶 Ortak türler';

  @override
  String musicViewAllShared(int count) {
    return 'Tümünü gör ($count)';
  }

  @override
  String get musicMatchDetailsCta => 'Bu müzik eşleşmesi neden?';

  @override
  String get profileEditSectionLanguages => 'Konuştuğun diller';

  @override
  String get profileEditSectionHobbies => 'Hobiler';

  @override
  String get profileEditSectionExtended => 'Profilini tamamla';

  @override
  String get profileLanguagesHint => 'Konuştuğun dilleri seç.';

  @override
  String get profileHobbiesHint => 'Seni anlatan hobileri seç.';

  @override
  String get profileHeightLabel => 'Boy';

  @override
  String profileHeightCm(int cm) {
    return '$cm cm';
  }

  @override
  String get profileHeight200Plus => '220+ cm';

  @override
  String get profileOccupationLabel => 'Meslek';

  @override
  String profileCompletionTitle(int percent) {
    return 'Profilin %$percent tamamlandı';
  }

  @override
  String profileCompletionMissing(String fields) {
    return 'Eksik alanlar: $fields';
  }

  @override
  String get profileFieldDisplayName => 'İsim';

  @override
  String get profileFieldBirthDate => 'Doğum tarihi';

  @override
  String get profileFieldGender => 'Cinsiyet';

  @override
  String get profileFieldInterestedIn => 'İlgilendiğin kişiler';

  @override
  String get profileFieldCity => 'Şehir';

  @override
  String get profileFieldPhotos => 'Fotoğraflar';

  @override
  String get profileFieldInterests => 'İlgi alanları';

  @override
  String get profileFieldRelationshipGoal => 'İlişki hedefi';

  @override
  String get profileFieldLanguages => 'Diller';

  @override
  String get profileFieldHeightCm => 'Boy';

  @override
  String get profileFieldBio => 'Biyografi';

  @override
  String get profileFieldEducation => 'Eğitim';

  @override
  String get profileFieldOccupation => 'Meslek';

  @override
  String get profileFieldHobbies => 'Hobiler';

  @override
  String get profileFieldLifestyleHabits => 'Yaşam tarzı alışkanlıkları';

  @override
  String get profileFieldLifestyleValues => 'Gelecek tercihleri';

  @override
  String get onboardingHeight => 'Boy';

  @override
  String get onboardingLanguages => 'Diller';

  @override
  String get profilePartnerSmokingPref => 'Partner sigara tercihi';

  @override
  String get profilePartnerDrinkingPref => 'Partner alkol tercihi';

  @override
  String get profileChildrenPreference => 'Çocuk istiyor musun?';

  @override
  String get profilePartnerChildrenPref => 'Partner çocuk tercihi';

  @override
  String get profileSocialRhythm => 'Sabah mı gece mi?';

  @override
  String get profileSocialLevel => 'Sosyal hayat';

  @override
  String get profileWeekendPreferences => 'Hafta sonu tercihleri';

  @override
  String get profileCohabitationPreference => 'Birlikte yaşam';

  @override
  String get partnerPrefNoIssue => 'Önemli değil';

  @override
  String get partnerPrefPrefer => 'Tercih ederim';

  @override
  String get partnerPrefPreferNot => 'Tercih etmem';

  @override
  String get partnerPrefNever => 'Kesinlikle istemem';

  @override
  String get childrenPrefYes => 'Evet';

  @override
  String get childrenPrefNo => 'Hayır';

  @override
  String get childrenPrefMaybe => 'Belki';

  @override
  String get childrenPrefUndecided => 'Henüz karar vermedim';

  @override
  String get socialRhythmMorning => 'Sabah insanıyım';

  @override
  String get socialRhythmNight => 'Gece insanıyım';

  @override
  String get socialRhythmVaries => 'Değişir';

  @override
  String get socialLevelVerySocial => 'Çok sosyalim';

  @override
  String get socialLevelBalanced => 'Dengeli';

  @override
  String get socialLevelQuiet => 'Daha sakinim';

  @override
  String get weekendFriendsOut => 'Arkadaşlarla dışarı';

  @override
  String get weekendHomeRelax => 'Evde dinlenmek';

  @override
  String get weekendSports => 'Spor';

  @override
  String get weekendTravel => 'Seyahat';

  @override
  String get weekendNature => 'Doğa';

  @override
  String get weekendParty => 'Parti';

  @override
  String get weekendFamily => 'Aile';

  @override
  String get weekendMovies => 'Film/dizi';

  @override
  String get cohabitationYes => 'İsterim';

  @override
  String get cohabitationMaybeLater => 'İleride olabilir';

  @override
  String get cohabitationUnsure => 'Emin değilim';

  @override
  String get cohabitationNo => 'İstemiyorum';

  @override
  String get languageGerman => 'Almanca';

  @override
  String get languageFrench => 'Fransızca';

  @override
  String get languageSpanish => 'İspanyolca';

  @override
  String get languageItalian => 'İtalyanca';

  @override
  String get languageRussian => 'Rusça';

  @override
  String get languageArabic => 'Arapça';

  @override
  String get languagePersian => 'Farsça';

  @override
  String get languageKurdish => 'Kürtçe';

  @override
  String get languageGreek => 'Yunanca';

  @override
  String get languageDutch => 'Hollandaca';

  @override
  String get languagePortuguese => 'Portekizce';

  @override
  String get languageChinese => 'Çince';

  @override
  String get languageJapanese => 'Japonca';

  @override
  String get languageKorean => 'Korece';

  @override
  String get hobbyWorkingOut => 'Spor yapmak';

  @override
  String get hobbyRunning => 'Koşu';

  @override
  String get hobbyFitness => 'Fitness';

  @override
  String get hobbySwimming => 'Yüzme';

  @override
  String get hobbyDancing => 'Dans';

  @override
  String get hobbyPhotography => 'Fotoğrafçılık';

  @override
  String get hobbyPainting => 'Resim';

  @override
  String get hobbyGaming => 'Oyun';

  @override
  String get hobbyCoding => 'Kodlama';

  @override
  String get hobbyCooking => 'Yemek yapmak';

  @override
  String get hobbyTravel => 'Seyahat';

  @override
  String get hobbyCamping => 'Kamp';

  @override
  String get hobbyHiking => 'Doğa yürüyüşü';

  @override
  String get hobbyPlayingInstrument => 'Enstrüman çalmak';

  @override
  String get hobbyReading => 'Okuma';

  @override
  String get hobbyYoga => 'Yoga';

  @override
  String get hobbyCycling => 'Bisiklet';

  @override
  String get hobbyTeamSports => 'Takım sporları';

  @override
  String get compatCategoryLanguages => 'Diller';

  @override
  String get compatCategoryHobbies => 'Hobiler';

  @override
  String get compatCategoryValues => 'Değerler & gelecek';

  @override
  String compatReasonSharedLanguages(String languages) {
    return 'İkiniz de $languages konuşuyorsunuz';
  }

  @override
  String compatReasonSharedHobbies(String hobbies) {
    return 'İkiniz de $hobbies yapmayı seviyorsunuz';
  }

  @override
  String get musicPrivacyNotice =>
      'Spotify verilerin yalnızca müzik uyumluluğunu hesaplamak ve eşleşmelerinde ortak dinleme bilgilerini göstermek için kullanılır. Tokenlar sunucuda kalır — cihazında tutulmaz.';

  @override
  String get musicDisconnectCta => 'Spotify bağlantısını kaldır';

  @override
  String get musicDisconnectConfirmTitle =>
      'Spotify bağlantısı kaldırılsın mı?';

  @override
  String get musicDisconnectConfirmBody =>
      'Spotify bağlantın ve önbellekteki müzik zevki verilerin silinir. Yeniden bağlanana kadar eşleşme müzik uyumu gösterilmez.';

  @override
  String get musicMatchTeaser =>
      '🎵 Müzik zevkiniz uyumlu olabilir — detaylar Premium ile';

  @override
  String get musicPremiumUnlock => 'Aç';

  @override
  String get musicNoCommonTracks => 'Henüz ortak dinlediğiniz bir şarkı yok 🎵';

  @override
  String get musicRecentlyPlayedHeading => 'Son dinlenenler';

  @override
  String get humorLabTitle => 'Mizah Labı';

  @override
  String get humorLabSubtitle =>
      'Sana farklı komik videolar ve görseller göstereceğiz. Hangilerinin seni gerçekten güldürdüğünü değerlendir. Ne kadar çok değerlendirirsen, mizah profilin o kadar doğru oluşur.';

  @override
  String get humorAttributionGiphy => 'Powered by GIPHY';

  @override
  String get humorAttributionYoutube => 'YouTube';

  @override
  String get humorAttributionGeneric => 'Kaynak';

  @override
  String get humorOpenOnYoutube => 'YouTube\'da aç';

  @override
  String get humorLabDiscoverCta => 'Mizah Labı\'nı aç';

  @override
  String get humorLoadingFeed => 'İçerikler hazırlanıyor…';

  @override
  String get humorRatingVeryFunny => 'Çok komik';

  @override
  String get humorRatingFunny => 'Komik';

  @override
  String get humorRatingNeutral => 'Nötr';

  @override
  String get humorRatingNotFunny => 'Komik değil';

  @override
  String get humorRatingNotAtAll => 'Hiç komik değil';

  @override
  String get humorProfileBuilding => 'Mizah vibesın hâlâ öğreniliyor…';

  @override
  String get humorProfileTitle => 'Mizah profilin';

  @override
  String get humorEmptyFeed => 'Şimdilik gösterecek yeni bir içerik yok.';

  @override
  String get humorFeedError => 'İçerik yüklenemedi. Tekrar dene.';

  @override
  String get humorTryAgain => 'Tekrar dene';

  @override
  String get humorUndoRating => 'Puanı geri al';

  @override
  String get humorCompatibilityTitle => 'Mizah uyumu';

  @override
  String get humorChatStarter => 'Beni güldüren bir şey…';

  @override
  String get humorTopVibes => 'Öne çıkan vibes';

  @override
  String get humorSaved => 'Kaydedildi';

  @override
  String get humorReport => 'Şikayet et';

  @override
  String get humorReportSuccess => 'Teşekkürler — bu içeriği inceleyeceğiz.';

  @override
  String get humorHowFunny => 'Ne kadar komik?';

  @override
  String get humorAdSponsoredLabel => 'Sponsorlu';

  @override
  String get humorAdPreparing => 'Reklam hazırlanıyor…';

  @override
  String get humorAdCompleted => 'Reklam tamamlandı.';

  @override
  String get humorAdContinue => 'Devam et';

  @override
  String humorAdCountdown(int seconds) {
    return 'Devam etmek için $seconds sn…';
  }

  @override
  String get humorPremiumAdFree => 'Premium ile reklamsız Mizah Labı';

  @override
  String get humorPremiumCardTitle => 'Premium';

  @override
  String get humorPremiumCardBody => 'Reklamsız Mizah Labı';

  @override
  String get humorPremiumCardCta => 'Premium\'u İncele';

  @override
  String get humorPremiumActiveBadge => 'Reklamsız Mizah Labı';

  @override
  String get humorMediaErrorSkip => 'İçerik yüklenemedi, sonrakine geçiliyor.';

  @override
  String get humorReportReasonOffensive => 'Rahatsız edici';

  @override
  String get humorReportReasonSpam => 'Spam';

  @override
  String get humorReportReasonMisleading => 'Yanıltıcı';

  @override
  String get humorReportReasonOther => 'Diğer';

  @override
  String get humorCategorySarcasm => 'İroni';

  @override
  String get humorCategoryAbsurd => 'Absürt';

  @override
  String get humorCategorySilly => 'Saçma sapan';

  @override
  String get humorCategoryRomantic => 'Romantik';

  @override
  String get humorCategoryDark => 'Kara mizah';

  @override
  String get humorCategoryMeme => 'Meme';

  @override
  String get humorCategoryDry => 'Kuru';

  @override
  String get humorCategoryWordplay => 'Kelime oyunu';

  @override
  String get humorCategorySituational => 'Durumsal';

  @override
  String get humorCategoryCringe => 'Cringe';

  @override
  String get humorCategoryTeasing => 'Takılma';

  @override
  String get humorIntroTitle => 'Mizahını keşfet';

  @override
  String get humorIntroBody1 =>
      'Sana farklı komik videolar ve görseller göstereceğiz.';

  @override
  String get humorIntroBody2 =>
      'Hangilerinin seni gerçekten güldürdüğünü değerlendir.';

  @override
  String get humorIntroBody3 =>
      'Ne kadar çok değerlendirirsen, mizah profilin o kadar kişiselleşir.';

  @override
  String get humorIntroCta => 'Mizahımı Keşfet';

  @override
  String get humorRatingHelp =>
      'Seçimlerin, sana uygun insanları keşfetmemize yardımcı olur.';

  @override
  String get humorRatingHelpDismiss => 'İpucunu gizle';

  @override
  String get humorHintFirstRating => 'Harika! Mizahını öğrenmeye başlıyoruz.';

  @override
  String get humorHintFiveRatings => 'Mizah profilin şekilleniyor.';

  @override
  String get humorHintTenRatings => 'Seni biraz daha tanıyoruz.';

  @override
  String get humorHintFifteenRatings =>
      'Mizah tercihlerin artık daha belirgin.';

  @override
  String get humorProgressTitle => 'Mizah profilin oluşuyor';

  @override
  String humorProgressCount(int count) {
    return '$count içerik değerlendirdin.';
  }

  @override
  String get humorProgressHint =>
      'Biraz daha değerlendirerek mizahını daha iyi keşfedebilirsin.';

  @override
  String get humorMilestoneShapingTitle => 'Mizahını biraz tanımaya başladık';

  @override
  String get humorMilestoneShapingBody =>
      'Verdiğin cevaplardan hangi mizah türlerini sevdiğini anlamaya başlıyoruz.';

  @override
  String get humorMilestoneProfileTitle => 'Senin mizah profilin';

  @override
  String get humorMilestoneProfileBody =>
      'Mizah tercihlerini daha net görmek için yeterli değerlendirme yaptın.';

  @override
  String get humorMilestoneViewProfile => 'Profilimi Gör';

  @override
  String get humorMilestoneContinue => 'Devam Et';

  @override
  String get humorProfileReadyTitle => 'Senin Mizah Profilin';

  @override
  String get humorProfileNotReady =>
      'Henüz yeterli veri yok — profilini netleştirmek için değerlendirmeye devam et.';

  @override
  String get humorProfileHowForms =>
      'Bu profil, Humor Lab\'da verdiğin cevaplardan zaman içinde oluşur. Ne kadar çok içerik değerlendirirsen, profilin o kadar kişiselleşir.';

  @override
  String get humorWhyMattersTitle => 'Bu neden önemli?';

  @override
  String get humorWhyMattersBody1 =>
      'Mevora\'da sadece ortak ilgi alanlarına değil, birlikte gülebileceğin insanlara da önem veriyoruz.';

  @override
  String get humorWhyMattersBody2 =>
      'Mizah profilin, ileride sana mizah anlayışı daha uyumlu insanları keşfetmene yardımcı olabilir.';

  @override
  String get humorHowCalculatedTitle => 'Nasıl hesaplanıyor?';

  @override
  String get humorHowCalculatedBody =>
      'Humor Lab\'da verdiğin değerlendirmelerden oluşur. Farklı mizah türlerine verdiğin tepkiler kişisel mizah profilini oluşturur. Profilin zaman içinde değişebilir. Mesaj içeriklerin bu profil için analiz edilmez.';

  @override
  String get humorPrivacyNote =>
      'Humor Lab\'daki seçimlerin mizah tercihlerini anlamak için kullanılır. Mesaj içeriklerin Humor Profile oluşturmak için analiz edilmez.';

  @override
  String get humorInfoTitle => 'Mizah Labı nasıl çalışıyor?';

  @override
  String get humorInfoStep1Title => 'İzle';

  @override
  String get humorInfoStep1Body => 'Sana farklı mizah içerikleri gösteriyoruz.';

  @override
  String get humorInfoStep2Title => 'Değerlendir';

  @override
  String get humorInfoStep2Body => 'Ne kadar komik bulduğunu seç.';

  @override
  String get humorInfoStep3Title => 'Mizah profilini oluştur';

  @override
  String get humorInfoStep3Body =>
      'Seçimlerinden kişisel mizah profilin oluşur.';

  @override
  String get humorInfoStep4Title => 'Daha uyumlu insanları keşfet';

  @override
  String get humorInfoStep4Body =>
      'Mizah anlayışın ileride uyumlu insanları bulmana yardımcı olabilir.';

  @override
  String get humorAdInfoTitle => 'Mizah Labı ücretsiz';

  @override
  String get humorAdInfoBody =>
      'Ücretsiz kullanımda zaman zaman reklam gösterilir.';

  @override
  String get humorAdInfoPremiumHint =>
      'Premium ile Mizah Labı\'nı reklamsız kullanabilirsin.';

  @override
  String get humorAdInfoPremiumCta => 'Premium\'u İncele';

  @override
  String get humorInfoTooltip => 'Mizah Labı nasıl çalışıyor?';
}
