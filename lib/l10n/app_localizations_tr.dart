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
  String get tagline =>
      'Mevora sana yüzlerce insan göstermek yerine, gerçekten uyum sağlayabileceğin kişileri seçmeye çalışır.';

  @override
  String get connectTagline => 'Sana uyan insanlarla tanış.';

  @override
  String get loginSlogan => 'Daha fazla insan değil. Sana daha uygun insanlar.';

  @override
  String get discoverBestMatchesTitle => 'Senin İçin';

  @override
  String get discoverBestMatchesSubtitle => 'Sana uygun olabilecek kişiler';

  @override
  String get onboardingUnderstandingMessage =>
      'Verdiğin cevapları sana daha uygun insanları seçebilmek için kullanıyoruz.';

  @override
  String get onboardingWhyRelationshipGoal =>
      'Aynı şeyi arayan insanları bulmamıza yardımcı olur.';

  @override
  String get onboardingWhyLifestyle =>
      'Günlük alışkanlıklar, zamanla sandığından daha önemli hale gelir.';

  @override
  String get onboardingWhyBio =>
      'Birkaç satır bile, seni tanımak isteyene nereden başlayacağını gösterir.';

  @override
  String get discoveryActionConnect => 'Beğen';

  @override
  String get discoveryActionPriorityIntro => 'Öncelikli tanışma';

  @override
  String get picksTitle => 'Mevora Picks';

  @override
  String get picksSubtitle => 'Sana özel seçtiklerimiz';

  @override
  String get picksHeadline => 'Bugünün Mevora Picks\'i';

  @override
  String picksIntroCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sana uygun olabileceğini düşündüğümüz $count kişi.',
      one: 'Sana uygun olabileceğini düşündüğümüz 1 kişi.',
    );
    return '$_temp0';
  }

  @override
  String get picksIntroNote =>
      'Rastgele değil, uyumuna göre seçildi. Her gün yenilenir.';

  @override
  String picksLowSupplyNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bugün senin için $count güçlü eşleşme bulduk. Çıtayı düşürmek yerine daha azını gösteriyoruz.',
      one:
          'Bugün senin için 1 güçlü eşleşme bulduk. Çıtayı düşürmek yerine daha azını gösteriyoruz.',
    );
    return '$_temp0';
  }

  @override
  String get picksLoading => 'Senin için kişileri seçiyoruz…';

  @override
  String get picksLoadErrorTitle => 'Picks\'ini yükleyemedik.';

  @override
  String get picksEmptyPreparingTitle => 'Bugün sana uygun birini seçemedik.';

  @override
  String get picksEmptyPreparingMessage =>
      'Sana rastgele profiller göstermek yerine daha anlamlı eşleşmeler buluyoruz.';

  @override
  String get picksEmptyDoneTitle => 'Bugünkü seçimlerini gördün.';

  @override
  String get picksDiscoveryOffTitle => 'Keşif kapalı';

  @override
  String get picksDiscoveryOffMessage =>
      'Picks alabilmek için ayarlardan keşfi aç.';

  @override
  String get picksLike => 'Beğen';

  @override
  String get picksPass => 'Geç';

  @override
  String picksLikeSemantics(String name) {
    return '$name kişisini beğen';
  }

  @override
  String picksPassSemantics(String name) {
    return '$name kişisini geç';
  }

  @override
  String picksOpenProfileSemantics(String name) {
    return '$name profilini aç';
  }

  @override
  String get picksActionFailed => 'İşlem tamamlanamadı. Tekrar dene.';

  @override
  String picksMatchScore(int score) {
    return 'Mevora uyumu %$score';
  }

  @override
  String get picksEmptyDoneMessage =>
      'Mevora yarın senin için yeni kişiler seçecek.';

  @override
  String get picksEmptyNoCandidatesMessage =>
      'Sana rastgele profiller göstermek yerine yarın yeniden bakacağız.';

  @override
  String get learningCardTitle => 'Bugünün soruları hazır';

  @override
  String learningCardTodayStart(int total) {
    return 'Bugünün $total kısa sorusu, sana daha uygun kişileri seçmemize yardımcı olacak.';
  }

  @override
  String learningCardTodayResume(int answered, int total) {
    return '$answered / $total tamamlandı. Kaldığın yerden devam et.';
  }

  @override
  String get learningCardStart => 'Başla';

  @override
  String get learningCardResume => 'Devam et';

  @override
  String get learningSkipToday => 'Bugünlük geç';

  @override
  String get learningRequiredTitle => 'Önce seni biraz tanıyalım';

  @override
  String learningRequiredBody(int total) {
    return 'Bugünkü seçimlerini cevaplarına göre hazırlayacağız. $total kısa soru, yaklaşık iki dakika.';
  }

  @override
  String get learningIntroTitle => 'Mevora seni her gün biraz daha tanısın';

  @override
  String learningIntroBody(int count) {
    return 'Bugünün $count kısa sorusu, sana daha uygun kişileri seçmemize yardımcı olacak.';
  }

  @override
  String learningIntroMeta(int count) {
    return '$count kısa soru · yaklaşık iki dakika';
  }

  @override
  String get learningIntroStart => 'Başlayalım';

  @override
  String learningProgress(int current, int total) {
    return '$current / $total';
  }

  @override
  String learningProgressSemantics(int current, int total) {
    return 'Soru $current, toplam $total';
  }

  @override
  String get learningPrevious => 'Önceki';

  @override
  String get learningNext => 'Sonraki';

  @override
  String get learningSaveFailed => 'Cevabın kaydedilemedi. Tekrar dene.';

  @override
  String get learningLoadErrorTitle => 'Sorular yüklenemedi.';

  @override
  String get learningDoneTitle => 'Bugünlük tamam.';

  @override
  String get learningDoneBody => 'Mevora artık seni biraz daha iyi tanıyor.';

  @override
  String get learningDoneContinue => 'Devam et';

  @override
  String get learningDoneTomorrow => 'Yarın yeni sorular seni bekliyor.';

  @override
  String get learningSkippedTitle => 'Tamam, yarın görüşürüz.';

  @override
  String get learningSkippedBody =>
      'İstersen bugünün sorularını Profil\'deki Mevora Beni Tanısın bölümünden yine cevaplayabilirsin.';

  @override
  String get learningProfileTitle => 'Mevora Beni Tanısın';

  @override
  String get learningProfileSubtitle =>
      'Cevapların, sana uygun kişileri seçmemize yardım eder.';

  @override
  String get learningAfterHumorTitle => 'Mizahını biraz tanıdık.';

  @override
  String get learningAfterHumorBody =>
      'Şimdi bugünün sorularıyla ilişkide senin için nelerin önemli olduğunu öğrenelim.';

  @override
  String get learningDashboardHeadline => 'Mevora seni ne kadar tanıyor?';

  @override
  String learningDashboardPercent(int percent) {
    return '%$percent';
  }

  @override
  String get learningDashboardBody =>
      'Cevapların ve profilin, sana daha uygun kişileri seçmemize yardım ediyor.';

  @override
  String learningDashboardThisMonth(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bu ay $count soru cevapladın',
      one: 'Bu ay 1 soru cevapladın',
      zero: 'Bu ay henüz soru cevaplamadın',
    );
    return '$_temp0';
  }

  @override
  String learningDashboardTotals(int total, int days) {
    return 'Toplam $total cevap · $days gün tamamlandı';
  }

  @override
  String learningDashboardToday(int answered, int total) {
    return 'Bugünün soruları ($answered/$total)';
  }

  @override
  String get learningDashboardTodayDone =>
      'Bugünlük tamam. Yarın yeni sorular gelecek.';

  @override
  String get learningDashboardCategoriesTitle => 'Uyum alanları';

  @override
  String get learningDashboardHighlightsTitle =>
      'Şimdiye kadar öğrendiklerimiz';

  @override
  String get learningDashboardHighlightsSubtitle => 'Kendi cevaplarından.';

  @override
  String get learningDashboardAnswersTitle => 'Cevapların';

  @override
  String get learningDashboardAnswersFooter =>
      'Fikrin değiştiyse bir cevaba dokunup değiştirebilirsin.';

  @override
  String get learningCategoryRelationship => 'İlişki beklentisi';

  @override
  String get learningCategoryCommunication => 'İletişim';

  @override
  String get learningCategoryLifestyle => 'Yaşam tarzı';

  @override
  String get learningCategoryValues => 'Değerler';

  @override
  String get learningCategoryHumor => 'Mizah';

  @override
  String get learningCategoryMusic => 'Müzik';

  @override
  String get learningCategoryInterests => 'İlgi alanları';

  @override
  String get pickTypeBestOverall => 'En iyi uyum';

  @override
  String get pickTypeValuesMatch => 'Değerler uyumu';

  @override
  String get pickTypeHumorMatch => 'Mizah uyumu';

  @override
  String get pickTypeMusicMatch => 'Müzik uyumu';

  @override
  String get pickTypeNearbyMatch => 'Yakınında';

  @override
  String get pickTypeUnexpectedMatch => 'Beklenmedik eşleşme';

  @override
  String get pickHeadlineBestOverallStrong => 'Genel uyumunuz çok yüksek.';

  @override
  String get pickHeadlineBestOverall => 'Genel uyumunuz güçlü.';

  @override
  String get pickHeadlineValues =>
      'İlişki beklentileriniz ve temel değerleriniz güçlü şekilde örtüşüyor.';

  @override
  String pickHeadlineHumorScore(int score) {
    return 'Mizah profiliniz %$score uyumlu.';
  }

  @override
  String pickHeadlineMusicArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ortak sanatçınız var.',
      one: 'Sevdiğiniz ortak bir sanatçı var.',
    );
    return '$_temp0';
  }

  @override
  String get pickHeadlineMusic => 'Müzik zevkinizde güçlü bir örtüşme var.';

  @override
  String get pickHeadlineNearby => 'Hem yakınında hem de güçlü bir eşleşme.';

  @override
  String get pickHeadlineUnexpected => 'Normalde gözden kaçırabileceğin biri.';

  @override
  String get pickDetailUnexpected =>
      'Ortak ilgi alanlarınız çok benzer olmayabilir ama ilişki beklentileri ve iletişim tarzınız güçlü şekilde uyuşuyor.';

  @override
  String pickWhyTitle(String name) {
    return 'Neden $name?';
  }

  @override
  String pickReasonOverall(int score) {
    return 'Mevora genel uyumunuz %$score.';
  }

  @override
  String get pickReasonRelationship =>
      'İkiniz de aynı türde bir ilişki arıyorsunuz.';

  @override
  String pickReasonViews(int aligned, int shared) {
    return '$shared ilişki sorusunun $aligned tanesinde aynı cevabı verdiniz.';
  }

  @override
  String get pickReasonCommunication =>
      'İletişim tarzlarınız uyumlu görünüyor.';

  @override
  String get pickReasonLifestyle => 'Yaşam tarzı tercihleriniz uyumlu.';

  @override
  String pickReasonHumorTraits(String traits) {
    return 'Ortak mizah tarzlarınız: $traits.';
  }

  @override
  String pickReasonMusicArtists(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Müzik profilinizde $count ortak sanatçı var.',
      one: 'Müzik profilinizde ortak bir sanatçı var.',
    );
    return '$_temp0';
  }

  @override
  String pickReasonMusicScore(int score) {
    return 'Müzik uyumunuz %$score.';
  }

  @override
  String pickReasonDistance(String distance) {
    return '$distance — buluşmak için yeterince yakın.';
  }

  @override
  String pickReasonInterests(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ortak ilgi alanınız var.',
      one: 'Ortak bir ilgi alanınız var.',
    );
    return '$_temp0';
  }

  @override
  String get compatScoreHeading => 'Uyum';

  @override
  String get compatTierStrong => 'Güçlü eşleşme';

  @override
  String get compatTierClose => 'Birçok konuda yakınsınız';

  @override
  String get compatTierNotable => 'Dikkate değer ortak noktalarınız var';

  @override
  String get compatTierSome => 'Bazı ortak noktalarınız var';

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
  String get loginSubtitle =>
      'Senin için seçtiklerimizi görmek için giriş yap.';

  @override
  String get createAccountTitle => 'Hesabını oluştur';

  @override
  String get registerSubtitle =>
      'Sana gerçekten uygun olabilecek insanlarla tanışmak için Mevora\'ya katıl.';

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
  String get phoneHint => '0532 123 4567';

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
      'Doğrulama kodunun süresi doldu. Yeni bir kod iste.';

  @override
  String get authSessionExpired =>
      'Oturumun süresi doldu. Lütfen numarayı tekrar gir.';

  @override
  String get authTooManyAttempts =>
      'Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar dene.';

  @override
  String get authSmsQuota =>
      'SMS gönderim sınırına ulaşıldı. Lütfen daha sonra tekrar dene.';

  @override
  String get authFirebaseUnavailable =>
      'Doğrulama servisine şu anda ulaşılamıyor. Lütfen daha sonra tekrar dene.';

  @override
  String get authNetwork => 'İnternet bağlantını kontrol et.';

  @override
  String get authDisabled =>
      'Bu hesap devre dışı bırakılmış. Bir hata olduğunu düşünüyorsan itiraz etmek için Mevora destek ekibine halilmertdeveliii@gmail.com adresinden yaz.';

  @override
  String get authBanned =>
      'Bu hesap topluluk kurallarımızı ihlal ettiği için kapatıldı. Bir hata olduğunu düşünüyorsan itiraz etmek için Mevora destek ekibine halilmertdeveliii@gmail.com adresinden yaz.';

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
  String get onboardingTitle => 'Seni biraz tanıyalım';

  @override
  String get onboardingMessage =>
      'Ne kadar iyi tanışırsak, sana gösterdiğimiz kişileri o kadar anlamlı seçebiliriz.';

  @override
  String get onboardingFirstName => 'Adın';

  @override
  String get onboardingLastName => 'Soyadın';

  @override
  String get onboardingLastNamePrivate => 'Soyadın diğer üyelere gösterilmez.';

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
  String get onboardingErrorBirthday => 'Doğum tarihini ekle.';

  @override
  String get onboardingErrorFirstName => 'Adını ekle.';

  @override
  String get onboardingErrorLastName => 'Soyadını ekle.';

  @override
  String get onboardingErrorGender => 'Kendini nasıl tanımladığını seç.';

  @override
  String get onboardingErrorInterestedIn => 'Kiminle tanışmak istediğini seç.';

  @override
  String get onboardingErrorCity => 'Şehrini seç.';

  @override
  String get onboardingErrorEducation => 'Eğitim durumunu seç.';

  @override
  String get onboardingErrorRelationshipGoal => 'Ne aradığını seç.';

  @override
  String get onboardingErrorLifestyle =>
      'Yaşam tarzı sorularının hepsini cevapla.';

  @override
  String onboardingErrorInterestsMax(int max) {
    return 'En fazla $max ilgi alanı seç.';
  }

  @override
  String onboardingErrorBioShort(int min) {
    return 'Kendinden en az $min karakterle bahset.';
  }

  @override
  String onboardingErrorBioLong(int max) {
    return 'En fazla $max karakter yazabilirsin.';
  }

  @override
  String onboardingErrorPhotosMax(int max) {
    return 'En fazla $max fotoğraf ekleyebilirsin.';
  }

  @override
  String get onboardingErrorPhotosInReview =>
      'Fotoğrafların hâlâ inceleniyor. Biraz sonra tekrar dene.';

  @override
  String get onboardingErrorProfileIncomplete =>
      'Bazı zorunlu bilgiler eksik. Geri dönüp tamamla.';

  @override
  String get onboardingErrorSignInAgain =>
      'Profilini tamamlamak için tekrar giriş yap.';

  @override
  String get onboardingErrorNotAllowed => 'Bu hesap kurulumu tamamlayamıyor.';

  @override
  String get onboardingErrorGeneric =>
      'Profilin tamamlanamadı. Lütfen tekrar dene.';

  @override
  String get onboardingBack => 'Geri';

  @override
  String get onboardingContinue => 'Devam et';

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
      'En az 3 tane seç. Ortak ilgi alanları, konuşacak bir şeyiniz olan insanları bulmamıza yardımcı olur.';

  @override
  String get onboardingBioHint => 'Kendinden biraz bahset.';

  @override
  String get onboardingPhotosHint =>
      'En az 3 fotoğraf ekle. En az bir fotoğrafta yüzün net görünmeli. Diğer fotoğraflarında hobilerini, seyahatlerini, evcil hayvanını veya hayatından detayları gösterebilirsin.';

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
      'Profilin hazır. Ne kadar iyi tanışırsak, sana gösterdiğimiz kişileri o kadar anlamlı seçebiliriz.';

  @override
  String get onboardingStartDiscovering => 'Seçtiklerimizi gör';

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
  String get locationPermissionTitle => 'Sana yakın insanları bulalım';

  @override
  String get locationPermissionMessage =>
      'Mevora konumunu, sana uygun ve gerçekten buluşabileceğin kadar yakın kişileri seçmek için kullanır.';

  @override
  String get locationPermissionSub =>
      'Konumun diğer kullanıcılara tam olarak gösterilmez. Yalnızca eşleşme ve mesafe hesaplamalarında kullanılır.';

  @override
  String get useMyLocation => 'Konumumu aç';

  @override
  String get notNow => 'Şimdilik atla';

  @override
  String get locationSkipHint =>
      'Konum, sana yakın kişileri seçmemize yardımcı olur. Daha sonra ayarlardan açabilirsin.';

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
      'Sana yakın kişileri seçebilmemiz için cihazının konum hizmetlerini açman gerekiyor.';

  @override
  String get locationDeniedMessage =>
      'Konum izni olmadan sana yakın kişileri seçemeyiz.';

  @override
  String get locationSuccessTitle =>
      'Harika. Artık sana yakın kişileri seçebiliriz.';

  @override
  String get locationLocating => 'Konumun belirleniyor...';

  @override
  String get locationPreparingMatches => 'Sana yakın kişileri seçiyoruz...';

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
  String get discoveryTitle => 'Seçimlerin hazırlanıyor';

  @override
  String get discoveryMessage =>
      'Sana uygun olabilecek kişiler burada görünecek.';

  @override
  String get discoveryEmptyTitle => 'Şimdilik seçimler bu kadar';

  @override
  String get discoveryEmptyMessage =>
      'Sana uygun olabilecek yeni kişiler bulduğumuzda burada göreceksin. İstersen mesafeni de genişletebilirsin.';

  @override
  String get discoverySeenEveryoneTitle => 'Şimdilik seçtiğimiz herkese baktın';

  @override
  String get discoverySeenEveryoneMessage =>
      'Sana uygun olabilecek yeni kişiler bulduğumuzda burada göreceksin.';

  @override
  String get exploreAgain => 'Tekrar bak';

  @override
  String get restartDemo => 'Demoyu yeniden başlat';

  @override
  String get discoveryFiltersTitle => 'Tercihlerin';

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
  String get whyYoureSeeingThis => 'Neden sana uygun olabilir?';

  @override
  String compatWhyThisPerson(String name) {
    return 'Neden $name?';
  }

  @override
  String get sharedInterests => 'Ortak ilgi alanları';

  @override
  String get profileDetailsTitle => 'Profil';

  @override
  String photoCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get tabDiscovery => 'Senin İçin';

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
    return 'Senin için seçildi · %$percent uyum';
  }

  @override
  String get like => 'Beğen';

  @override
  String get pass => 'Geç';

  @override
  String get superLike => 'Süper Beğeni';

  @override
  String get itsAMatch => 'Birbirinizi seçtiniz';

  @override
  String get youLikedEachOther => 'İkiniz de evet dediniz.';

  @override
  String get sendMessage => 'Mesaj gönder';

  @override
  String get startChat => 'Merhaba de';

  @override
  String get keepSwiping => 'Seçimlerine dön';

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
  String get discoveryPreferences => 'Eşleşme tercihleri';

  @override
  String get settingsPersonalizeRecommendations =>
      'Önerilerimi etkileşimlerime göre kişiselleştir';

  @override
  String get settingsPersonalizeRecommendationsSubtitle =>
      'Beğeniler, eşleşmeler ve konuşma etkinliği gibi sinyalleri kullanarak önerilerini zamanla sana göre ayarlarız. Mesajlarının içeriğini analiz etmeyiz.';

  @override
  String get settingsResetLearned =>
      'Mevora\'nın benden öğrendiklerini sıfırla';

  @override
  String get settingsResetLearnedSubtitle =>
      'Etkileşimlerinden öğrenilenler silinir. Verdiğin cevaplar kalır.';

  @override
  String get settingsResetLearnedConfirmTitle => 'Öğrenilenler sıfırlansın mı?';

  @override
  String get settingsResetLearnedConfirmBody =>
      'Mevora beğenilerinden, eşleşmelerinden ve konuşma etkinliğinden öğrendiklerini unutacak. Cevapların ve profilin değişmez.';

  @override
  String get settingsResetLearnedConfirm => 'Sıfırla';

  @override
  String get settingsResetLearnedDone => 'Öğrenilenler sıfırlandı.';

  @override
  String get settingsResetLearnedFailed => 'Sıfırlanamadı. Tekrar dene.';

  @override
  String get minAge => 'En düşük yaş';

  @override
  String get maxAge => 'En yüksek yaş';

  @override
  String get maxDistance => 'En fazla mesafe';

  @override
  String get matchesTitle => 'Eşleşmelerin';

  @override
  String get matchesSubtitle =>
      'Birbirinizi seçtiğiniz kişiler, uyumunuza göre sıralı.';

  @override
  String get matchesEmptyTitle => 'Eşleşmelerin burada görünecek';

  @override
  String get matchesEmptyMessage =>
      'Biriyle birbirinizi seçtiğinizde onu burada, ortak noktalarınızla birlikte bulacaksın.';

  @override
  String get newMatch => 'Yeni eşleşme';

  @override
  String get connectionBadgeNew => 'Yeni eşleşme';

  @override
  String get connectionBadgeActive => 'Aktif sohbet';

  @override
  String matchStrongestConnectionLabel(String category) {
    return 'En güçlü olduğunuz alan: $category';
  }

  @override
  String get compatStrongestRelationship => 'Aynı şeyi arıyorsunuz';

  @override
  String get compatStrongestValues => 'Hayata bakışınız benzer';

  @override
  String get compatStrongestQuestions => 'Birçok soruya benzer cevap verdiniz';

  @override
  String get compatStrongestMusic =>
      'Müzik zevkinizde güçlü ortak noktalar var';

  @override
  String get compatStrongestLifestyle => 'Yaşam tarzlarınız birbirine yakın';

  @override
  String get compatStrongestInterests => 'Benzer şeylerden keyif alıyorsunuz';

  @override
  String get compatStrongestCommunication =>
      'Benzer şekilde iletişim kuruyorsunuz';

  @override
  String get compatStrongestLanguages => 'Ortak bir diliniz var';

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
      'Mesajlarınızı yalnızca sen ve bu kişi okuyabilir.';

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
  String get blockConfirmTitle => 'Bu kişi engellensin mi?';

  @override
  String get blockConfirmMessage =>
      'Bu kişiyi sana bir daha göstermeyiz; mesajlaşamaz ve birbirinizi arayamazsınız.';

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
  String get hideProfileMessage => 'Bu kişiyi sana bir daha göstermeyiz.';

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
  String get exportMyDataShareSubject => 'Mevora veri dışa aktarımım';

  @override
  String get exportMyDataShared => 'Veri dışa aktarımın paylaşıldı.';

  @override
  String get exportMyDataReady =>
      'Veri dışa aktarımın hazır. Kaydetmek veya göndermek için bir uygulama seç.';

  @override
  String get exportMyDataShareUnavailable =>
      'Bu cihazda dışa aktarımı alabilecek bir uygulama yok.';

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
  String get notificationNewMatch => 'Yeni bir eşleşmen var';

  @override
  String get notificationNewMessage => 'Yeni bir mesajın var';

  @override
  String get notificationSuperLike => 'Birisi seni Süper Beğendi';

  @override
  String get boostTitle => 'Smart Boost';

  @override
  String get boostSubtitle =>
      'Boost aktifken profilin, seninle uyumu yüksek kişilere daha önce ve biraz daha geniş bir alanda gösterilir.';

  @override
  String get boostDuration => 'Profilini öne çıkar';

  @override
  String get boostActivate => 'Kalan bakiyeyi kullan';

  @override
  String get boostBuy => 'Boost satın al';

  @override
  String get boostOneTimePurchaseNote =>
      'Boost tek seferlik bir satın almadır. Kendiliğinden yenilenmez.';

  @override
  String get boostPurchasing => 'Satın alma işlemi başlatılıyor...';

  @override
  String get boostVerifying => 'Satın alma doğrulanıyor...';

  @override
  String get boostSuccessTitle => 'Boost aktif';

  @override
  String get boostSuccessMessage =>
      'Boost aktif. Süresi boyunca profilin, seninle uyumu yüksek kişilere daha önce gösterilir.';

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
  String get boostBackToDiscovery => 'Senin İçin\'e dön';

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
  String percentValue(int value) {
    return '%$value';
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
      'Mevora konumunu, mesafeyi göstermek ve sana yakın kişileri seçmek için kullanır.';

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
  String get photoUploadFailed => 'Fotoğraf yüklenemedi. Lütfen tekrar dene.';

  @override
  String get photoNoneSelected => 'Fotoğraf seçilmedi.';

  @override
  String get photoNeedSignIn => 'Fotoğraf yüklemek için giriş yapmalısın.';

  @override
  String get photoInvalidFile => 'Bu fotoğraf türü veya boyutu uygun değil.';

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
  String get settingsLastNameRequired => 'Soyad gerekli.';

  @override
  String get settingsLastNameTooLong => 'Soyad çok uzun.';

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
  String get settingsSuperLikeNotifications => 'Süper Beğeni bildirimleri';

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
  String get discoveryLoading => 'Senin için kişileri seçiyoruz...';

  @override
  String get discoveryLoadErrorTitle => 'Seçimlerin yüklenemedi';

  @override
  String get discoveryLoadErrorMessage =>
      'Bağlantını kontrol et ve tekrar dene.';

  @override
  String get discoveryChangePreferences => 'Tercihlerini değiştir';

  @override
  String get itsAMatchHeadline => 'Yeni eşleşme';

  @override
  String get matchCelebrationLead => 'Birbirinizi seçtiniz';

  @override
  String get matchCelebrationInsight =>
      'Artık konuşmaya başlayabilirsiniz. İşte sizi yakınlaştıran şeyler.';

  @override
  String get demoProfileBadge => 'Örnek';

  @override
  String sharedHobbiesCount(int count) {
    return '$count ortak ilgi alanı';
  }

  @override
  String get tabSettings => 'Ayarlar';

  @override
  String get tabMusic => 'Müzik';

  @override
  String get musicTitle => 'Müzik';

  @override
  String get musicConnectCta => 'Spotify\'ı bağla';

  @override
  String get musicConnected => 'Spotify bağlı';

  @override
  String get musicUnconnectedHeadline =>
      'Müzik zevkin de eşleşmenin bir parçası olsun';

  @override
  String get musicUnconnectedCopy =>
      'Mevora, sevdiğin sanatçılara ve parçalara bakarak başkalarıyla ortak müzik zevkini görür. Bu, uyumun yalnızca bir parçasıdır; tek başına belirlemez.';

  @override
  String get musicConnecting => 'Spotify bağlanıyor…';

  @override
  String get musicSyncing => 'Müzik zevkin yenileniyor…';

  @override
  String get musicRefresh => 'Müzik verilerini yenile';

  @override
  String get musicRefreshCooldown => 'Daha sonra tekrar yenileyebilirsin.';

  @override
  String get musicProfileTitle => 'Müzik profilin';

  @override
  String get musicSameTasteTitle => 'Seninle aynı müziği dinleyenler';

  @override
  String get musicSameTasteEmpty =>
      'Henüz örtüşen bir müzik zevki yok. Biraz dinledikten sonra yenile.';

  @override
  String get musicWeeklyTitle => 'Bu haftanın müzikleri';

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
  String get settingsConnectSpotify => 'Spotify\'ı bağla';

  @override
  String get settingsSpotifySubtitle =>
      'Müzik zevkin de eşleşmenin bir parçası olsun. Mevora müzik çalmaz.';

  @override
  String get likesYouTitle => 'Seni beğenenler';

  @override
  String get likesYouEntrySubtitle => 'Neden uyumlu olabileceğinize bak';

  @override
  String get likesYouInsightSubtitle =>
      'Karar vermeden önce ortak noktalarınıza bakmak için dokun.';

  @override
  String likesYouCompatibilityLabel(int score) {
    return '%$score uyum';
  }

  @override
  String get likesYouSeeWhy => 'Neden bu kişi?';

  @override
  String get likesYouLockedTitle => 'Seninle ilgilenenleri gör';

  @override
  String likesYouLockedCount(int count) {
    return '$count kişi seni beğendi';
  }

  @override
  String get likesYouLockedMessage =>
      'Seni kimlerin beğendiğini ve neden uyumlu olabileceğinizi görmek için Premium\'a geç. İsimler ve fotoğraflar o zamana kadar gizli kalır.';

  @override
  String get likesYouUnlockCta => 'Premium ile aç';

  @override
  String get likesYouBlurredHint =>
      'Her kutu gerçek bir kişi. Premium kim olduğunu ve neden uyduğunuzu gösterir.';

  @override
  String get likesYouHiddenName => 'Gizli profil';

  @override
  String get likesYouHiddenSubtitle =>
      'Ortak noktalarınızı görmek için kilidi aç';

  @override
  String get likesYouEmptyTitle => 'Henüz beğeni yok';

  @override
  String get likesYouEmptyMessage =>
      'Biri seni beğendiğinde onu burada, neden uyumlu olabileceğinizle birlikte göreceksin.';

  @override
  String get likesYouLoadError => 'Beğeniler yüklenemedi. Lütfen tekrar dene.';

  @override
  String get relationshipMatchBadge => 'Benzer cevaplar';

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
  String get relationshipMatchesEmpty =>
      'Senin gibi düşünen insanları bulmak için birkaç ilişki sorusu yanıtla — burada mesafe önemli değil.';

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
      'Doğrulaman, güvenli bir doğrulama sağlayıcısı tarafından yapılır.';

  @override
  String get followVerificationInstructions =>
      'Kendini doğrulamak için talimatları izle.';

  @override
  String get verificationNotConfigured =>
      'Doğrulama geçici olarak kullanılamıyor.';

  @override
  String get verificationCooldown =>
      'Tekrar denemeden önce birkaç dakika bekle.';

  @override
  String get verificationAttemptLimit =>
      'Bugünkü doğrulama sınırına ulaştın. Yarın tekrar dene.';

  @override
  String get verificationProcessing =>
      'Doğrulamanı kontrol ediyoruz. Bu genelde bir dakika sürer.';

  @override
  String get verificationUnderReview =>
      'Doğrulaman inceleniyor. Sonuçlandığında bu sayfayı güncelleyeceğiz.';

  @override
  String get verificationCheckAgain => 'Tekrar kontrol et';

  @override
  String get verificationExpired =>
      'Bu doğrulama oturumu tamamlanmadan süresi doldu. Yeni bir tane başlatabilirsin.';

  @override
  String get verificationTemporaryError =>
      'Doğrulama durumunu şu anda okuyamadık. Birazdan tekrar dene.';

  @override
  String get verificationDeclinedDocument =>
      'Kimliğini net okuyamadık. İyi ışıkta, belgenin tamamı kadrajda olacak şekilde tekrar dene.';

  @override
  String get verificationDeclinedLiveness =>
      'Selfie adımı tamamlanmadı. Aydınlık bir yerde, doğrudan kameraya bakarak tekrar dene.';

  @override
  String get verificationDeclinedFaceMatch =>
      'Selfie, kimliğindeki fotoğrafla eşleşmedi. Tekrar dene veya farklı bir belge kullan.';

  @override
  String get verificationOpensProvider =>
      'Kimliğini taratıp selfie çekmen için doğrulama partnerimize yönlendirileceksin, sonra buraya döneceksin.';

  @override
  String get whyYouMatch => 'Neden sana uygun olabilir?';

  @override
  String get compatWhyButton => 'Neden?';

  @override
  String compatDiscoverBadge(int percent) {
    return '%$percent uyum';
  }

  @override
  String get compatCalculating => 'Hesaplanıyor...';

  @override
  String get compatUnavailable => 'Uyum henüz hesaplanamadı';

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
      'Birkaç ilişki sorusu cevapla; hem insanlar hem Mevora seni daha iyi tanısın. İstediğin zaman düzenleyebilirsin.';

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
  String get questionAnswersMatchedSubtitle => 'Ortak yönlerinize bak.';

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
    return '%$percent uyum';
  }

  @override
  String get compatNotEnoughData => 'Henüz yeterli bilgi yok';

  @override
  String get compatStrongestConnection => 'En çok ortak olduğunuz nokta';

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
  String get compatReasonSameRelationshipGoal => 'Aynı şeyi arıyorsunuz';

  @override
  String get compatReasonGoalLongTerm =>
      'İkiniz de uzun süreli bir ilişki arıyorsunuz';

  @override
  String get compatReasonGoalShortTerm =>
      'İkiniz de daha rahat bir ilişki arıyorsunuz';

  @override
  String get compatReasonGoalFriendship =>
      'İkiniz de yeni arkadaşlıklar arıyorsunuz';

  @override
  String get compatReasonGoalNotSure =>
      'İkiniz de ne aradığınızı henüz netleştiriyorsunuz';

  @override
  String compatReasonSharedInterests(String interests) {
    return 'İkiniz de $interests seviyorsunuz';
  }

  @override
  String get compatReasonSomeSharedInterests => 'Ortak ilgi alanlarınız var';

  @override
  String get compatReasonSimilarLifestyle =>
      'Yaşam tarzlarınız birbirine yakın';

  @override
  String compatReasonSameAnswers(String aligned, String shared) {
    return '$shared sorunun $aligned tanesine aynı cevabı verdiniz';
  }

  @override
  String get compatReasonSimilarViews =>
      'İlişki sorularına benzer cevaplar verdiniz';

  @override
  String get compatReasonSimilarMusic =>
      'Müzik zevkinizde güçlü ortak noktalar var';

  @override
  String get compatReasonCommunication =>
      'Benzer şekilde iletişim kuruyorsunuz';

  @override
  String get hiddenCompatTitle => 'Seninle benzer düşünen biri var';

  @override
  String hiddenCompatMessage(int count) {
    return '$count soruya seninle aynı cevabı verdi.';
  }

  @override
  String hiddenCompatCompatibility(int percent) {
    return '%$percent uyum';
  }

  @override
  String get hiddenCompatCta => 'Kim olduğuna bak';

  @override
  String get hiddenCompatDismiss => 'Şimdi değil';

  @override
  String get supportCenterTitle => 'Yardım ve Destek';

  @override
  String get supportCenterSubtitle =>
      'Yanıtları bul, politikaları incele veya ekibimize ulaş.';

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
  String get supportFaqEmpty => 'Aramanla eşleşen soru bulunamadı.';

  @override
  String get supportCreateTicket => 'Destek Talebi Oluştur';

  @override
  String get supportCreateTicketSubtitle =>
      'Sorununu anlat, istersen ekran görüntüsü ekle';

  @override
  String get supportMyTickets => 'Destek Taleplerim';

  @override
  String get supportTicketsEmptyTitle => 'Henüz destek talebi yok';

  @override
  String get supportTicketsEmptyMessage =>
      'Destek ekibine yazdığında taleplerin burada görünür.';

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
  String get supportTicketSubmitted => 'Destek talebin gönderildi.';

  @override
  String get supportTicketFailed => 'Talep gönderilemedi. Tekrar dene.';

  @override
  String get supportTicketValidation => 'Konu ve mesaj zorunludur.';

  @override
  String get supportTicketDetailTitle => 'Destek talebi';

  @override
  String get supportTicketNotFoundTitle => 'Destek talebi bulunamadı';

  @override
  String get supportTicketNotFoundMessage =>
      'Bu destek talebi artık yok ya da hesabına ait değil.';

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
      'Ayarlar → Hesap → Hesabı Sil yolunu izle. Onayladığında Mevora hesabın ve ilişkili verilerin kalıcı olarak silinir. Bu işlem geri alınamaz.';

  @override
  String get faqChangePhotoQ => 'Profil fotoğrafımı nasıl değiştiririm?';

  @override
  String get faqChangePhotoA =>
      'Ayarlar → Profili Düzenle\'ye git. Galeriden veya kameradan fotoğraf ekleyebilir, kaldırabilir ya da değiştirebilirsin. Fotoğraflar başkalarına gösterilmeden önce incelenebilir.';

  @override
  String get faqCloseAccountQ => 'Hesabımı nasıl kapatırım?';

  @override
  String get faqCloseAccountA =>
      'Hesabı kapatmak, silmekle aynıdır. Ayarlar → Hesap → Hesabı Sil\'i kullan. Yalnızca çıkış yapmak verilerini silmez.';

  @override
  String get faqHowMatchQ => 'Eşleşme nasıl oluşuyor?';

  @override
  String get faqHowMatchA =>
      'Mevora sana uygun olabilecek kişileri seçer. Biriyle birbirinizi beğendiğinizde eşleşirsiniz ve Eşleşmeler sekmesinden mesajlaşabilirsiniz.';

  @override
  String get faqMatchPercentQ => 'Uyum yüzdesi ne anlama geliyor?';

  @override
  String get faqMatchPercentA =>
      'Cevaplarına, ilgi alanlarına, yaşam tarzına, müzik zevkine ve diğer sinyallere dayanan bir uyum tahminidir. Mevora\'nın birini neden senin için seçtiğini anlamana yardımcı olur; asla bir garanti değildir.';

  @override
  String get faqCantMessageQ => 'Neden mesaj gönderemiyorum?';

  @override
  String get faqCantMessageA =>
      'Mesajlaşma yalnızca aktif eşleşmelerde açıktır. Eşleşme sona erdiyse, biriniz diğerini engellediyse ya da sohbet kapandıysa mesaj gönderemezsin.';

  @override
  String get faqNotificationsQ => 'Bildirimleri nasıl yönetebilirim?';

  @override
  String get faqNotificationsA =>
      'Eşleşme, mesaj ve diğer bildirimleri Ayarlar → Bildirimler\'den yönetebilirsin. Cihaz ayarlarından da bildirim izni vermen gerekebilir.';

  @override
  String get faqBlockQ => 'Birini nasıl engellerim?';

  @override
  String get faqBlockA =>
      'Sohbette Daha fazla → Engelle\'ye dokun. Profilde güvenlik menüsünden Engelle\'yi seç. Engellediğin kişiler sana mesaj gönderemez ve eşleşmelerinde görünmez.';

  @override
  String get faqReportQ => 'Birini nasıl şikayet ederim?';

  @override
  String get faqReportA =>
      'Profil veya sohbetteki güvenlik menüsünden Şikayet et\'i seç, bir neden belirt ve istersen açıklama ekle. Şikayetler ekibimiz tarafından incelenir.';

  @override
  String get faqStaySafeQ => 'Mevora\'da güvenliğimi nasıl korurum?';

  @override
  String get faqStaySafeA =>
      'İlk buluşmalarda kalabalık yerleri seç, güvenene kadar kişisel bilgilerini paylaşma, engelle ve şikayet araçlarını kullan, Topluluk Kuralları\'na göz at.';

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
    return 'Müzik uyumu · %$percent';
  }

  @override
  String get musicInsightBandHigh =>
      'Müzik zevkinizde güçlü ortak noktalar var.';

  @override
  String get musicInsightBandMid =>
      'Müzik zevkinizde belirgin ortak noktalar var.';

  @override
  String get musicInsightBandLow => 'Müzik zevkiniz bazı noktalarda kesişiyor.';

  @override
  String musicInsightSharedTracks(int count) {
    return '$count ortak şarkınız var.';
  }

  @override
  String musicInsightSharedArtists(int count) {
    return '$count ortak sanatçınız var.';
  }

  @override
  String musicInsightSharedPlaylistTracks(int count) {
    return 'Playlistlerinizde $count ortak şarkı var.';
  }

  @override
  String musicInsightSharedRecentTracks(int count) {
    return 'Son dönemde $count aynı şarkıyı dinlemişsiniz.';
  }

  @override
  String musicInsightTopSharedArtist(String name) {
    return 'İkiniz de $name\'i sık dinliyorsunuz.';
  }

  @override
  String musicInsightTopSharedGenres(String genres) {
    return 'Müzik zevkinizin büyük kısmı $genres türlerinde kesişiyor.';
  }

  @override
  String get musicInsightDataUnavailable =>
      'Karşılaştırma için henüz yeterli Spotify verisi yok.';

  @override
  String get musicSpotifyNotConnected => 'Spotify bağlı değil';

  @override
  String get musicSharedTracksHeading => 'Ortak şarkılarınız';

  @override
  String get musicSharedArtistsHeading => 'Ortak sanatçılarınız';

  @override
  String get musicSharedGenresHeading => 'Ortak türler';

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
  String get profileEditSectionExtended => 'Seni daha iyi tanıyalım';

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
  String get profileCompletionHeadline =>
      'Seni daha iyi tanımamıza yardımcı ol';

  @override
  String get profileCompletionBody =>
      'Profilindeki bilgiler, sana daha anlamlı seçimler sunmamıza yardımcı olur.';

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
  String get languageGerman => 'Almanca 🇩🇪';

  @override
  String get languageFrench => 'Fransızca 🇫🇷';

  @override
  String get languageSpanish => 'İspanyolca 🇪🇸';

  @override
  String get languageItalian => 'İtalyanca 🇮🇹';

  @override
  String get languageRussian => 'Rusça 🇷🇺';

  @override
  String get languageArabic => 'Arapça 🌐';

  @override
  String get languagePersian => 'Farsça 🌐';

  @override
  String get languageKurdish => 'Kürtçe 🌐';

  @override
  String get languageGreek => 'Yunanca 🇬🇷';

  @override
  String get languageDutch => 'Hollandaca 🇳🇱';

  @override
  String get languagePortuguese => 'Portekizce 🇵🇹';

  @override
  String get languageChinese => 'Çince 🌐';

  @override
  String get languageJapanese => 'Japonca 🇯🇵';

  @override
  String get languageKorean => 'Korece 🇰🇷';

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
    return 'İkiniz de şunlardan keyif alıyorsunuz: $hobbies';
  }

  @override
  String get musicPrivacyNotice =>
      'Spotify verilerin yalnızca müzik uyumunu hesaplamak ve eşleşmelerinde ortak dinleme bilgilerini göstermek için kullanılır. Tokenlar sunucuda kalır, cihazında tutulmaz.';

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
      'Müzik zevkiniz örtüşüyor olabilir. Ayrıntıları Premium ile gör.';

  @override
  String get musicPremiumUnlock => 'Aç';

  @override
  String get musicNoCommonTracks => 'Henüz ortak dinlediğiniz bir şarkı yok';

  @override
  String get musicRecentlyPlayedHeading => 'Son dinlenenler';

  @override
  String get humorLabTitle => 'Mizah Labı';

  @override
  String get humorLabSubtitle => 'Neye güldüğünü öğrenmeye devam edelim.';

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
  String get humorProfileBuilding => 'Mizah tarzın hâlâ öğreniliyor…';

  @override
  String get humorProfileTitle => 'Mizah profilin';

  @override
  String get humorEmptyFeed => 'Şimdilik gösterecek yeni bir içerik yok.';

  @override
  String get humorFeedError => 'İçerik yüklenemedi. Tekrar dene.';

  @override
  String get humorTryAgain => 'Tekrar dene';

  @override
  String get humorUndoRating => 'Önceki içeriğe dön';

  @override
  String get humorCompatibilityTitle => 'Mizah uyumu';

  @override
  String get humorChatStarter =>
      'Mizah anlayışlarımız benziyor gibi — bugün seni ne güldürdü?';

  @override
  String get humorChatStarterSarcasm =>
      'İkimiz de ironiyi seviyoruz galiba — bugün seni ne güldürdü?';

  @override
  String get humorChatStarterAbsurd =>
      'Absürt mizah ikimize de hitap ediyor gibi — son gördüğün en absürt şey neydi?';

  @override
  String get humorChatStarterSilly =>
      'Saçma sapan şeylere ikimiz de gülüyoruz galiba — en son neye kahkaha attın?';

  @override
  String get humorChatStarterRomantic =>
      'Romantik mizah ikimize de hitap ediyor gibi — en sevdiğin romantik komedi hangisi?';

  @override
  String get humorChatStarterDark =>
      'Kara mizahta anlaşıyoruz galiba — seni en son hangi espri yakaladı?';

  @override
  String get humorChatStarterMeme =>
      'İkimiz de meme insanıyız galiba — şu an en sevdiğin meme hangisi?';

  @override
  String get humorChatStarterDry =>
      'Kuru mizah ikimizin de tarzı gibi — bildiğin en iyi tek satırlık espri ne?';

  @override
  String get humorChatStarterWordplay =>
      'Kelime oyunlarına ikimiz de bayılıyoruz galiba — en sevdiğin kelime oyunu hangisi?';

  @override
  String get humorChatStarterSituational =>
      'Gündelik hayatın komik anları ikimizi de güldürüyor gibi — son zamanlarda başına gelen en komik şey neydi?';

  @override
  String get humorChatStarterCringe =>
      'Cringe içerikler ikimizi de güldürüyor galiba — son gördüğün en cringe şey neydi?';

  @override
  String get humorChatStarterTeasing =>
      'Tatlı tatlı takılmayı ikimiz de seviyoruz galiba — ilk laf benden mi, senden mi?';

  @override
  String get humorCompatibilityLevelHigh => 'Mizahınız çok yakın';

  @override
  String get humorCompatibilityLevelMedium => 'Benzer şeylere gülüyorsunuz';

  @override
  String get humorCompatibilityLevelLow =>
      'Mizahınız bazı noktalarda buluşuyor';

  @override
  String get humorCompatibilityBuilding =>
      'Mizah uyumunuzu görmek için ikinizin de mizah profilini tamamlaması gerekiyor.';

  @override
  String get humorCompatibilitySharedStyles => 'Ortak mizah tarzlarınız';

  @override
  String get humorCompatibilityNote =>
      'Bu, ikinizin mizah içeriklerine verdiği tepkilerden çıkan hafif bir işaret; ilişkiniz hakkında kesin bir şey söylemez.';

  @override
  String get humorTopVibes => 'Öne çıkan tarzların';

  @override
  String get humorReport => 'Şikayet et';

  @override
  String get humorReportSuccess => 'Teşekkürler — bu içeriği inceleyeceğiz.';

  @override
  String get humorHowFunny => 'Ne kadar komik?';

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
  String get humorMediaUnavailable => 'Bu içerik şu anda gösterilemiyor.';

  @override
  String get humorVideoLoadFailed => 'Video yüklenemedi';

  @override
  String get humorMediaNext => 'Sonraki';

  @override
  String get humorAttributionVerified => 'Doğrulanmış içerik üreticisi';

  @override
  String get boostResultsTitle => 'Boost sonuçları';

  @override
  String get boostResultsPending => 'Sonuçlar sayılıyor…';

  @override
  String boostReachedPeople(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kişiye gösterildin',
      one: '1 kişiye gösterildin',
      zero: 'Henüz kimseye gösterilmedi',
    );
    return '$_temp0';
  }

  @override
  String boostLikesReceived(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beğeni',
      one: '1 beğeni',
      zero: '0 beğeni',
    );
    return '$_temp0';
  }

  @override
  String boostMatchesCreated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eşleşme',
      one: '1 eşleşme',
      zero: '0 eşleşme',
    );
    return '$_temp0';
  }

  @override
  String get boostCompletedTitle => 'Boost tamamlandı';

  @override
  String get boostCompletedEmpty => 'Bu Boost kimseye ulaşmadı.';

  @override
  String get boostResultsUnavailable => 'Bu Boost için sonuç bilgisi yok.';

  @override
  String get boostResultsDelayNote =>
      'Sayılar canlı etkinliğin biraz gerisinde kalabilir.';

  @override
  String get onboardingMusicTitle =>
      'Müzik zevkin de eşleşmenin bir parçası olsun';

  @override
  String get onboardingMusicBody =>
      'Spotify\'ı bağlarsan Mevora sevdiğin sanatçılara ve parçalara da bakar, biriyle ortak müzik zevkinizi sana gösterir. Müzik, eşleşmeyi tek başına belirlemez.';

  @override
  String get onboardingMusicConnect => 'Spotify\'ı bağla';

  @override
  String get onboardingMusicSkip => 'Şimdilik geç';

  @override
  String get onboardingMusicSkipNote =>
      'Spotify\'ı sonra Müzik sekmesinden bağlayabilirsin.';

  @override
  String get onboardingMusicCancelled =>
      'Spotify bağlantısı iptal edildi. Tekrar deneyebilir veya geçebilirsin.';

  @override
  String get publicMusicTitle => 'Spotify zevkini yakaladık';

  @override
  String get publicMusicSubtitle => 'Profilinde göstermek istediklerini seç.';

  @override
  String get publicMusicArtistsHeading => 'Sanatçılar';

  @override
  String get publicMusicTracksHeading => 'Şarkılar';

  @override
  String publicMusicArtistCount(int count, int max) {
    return '$count/$max sanatçı seçildi';
  }

  @override
  String publicMusicTrackCount(int count, int max) {
    return '$count/$max şarkı seçildi';
  }

  @override
  String get publicMusicLimitReached =>
      'Üst sınıra ulaştın. Başkasını seçmek için birini kaldır.';

  @override
  String get publicMusicSave => 'Profilime ekle';

  @override
  String get publicMusicSaveFailed =>
      'Seçimini kaydedemedik. Lütfen tekrar dene.';

  @override
  String get publicMusicEmpty =>
      'Spotify henüz yeterli dinleme verisi döndürmedi. Müziğin bağlı kalmaya ve uyum hesabında kullanılmaya devam ediyor.';

  @override
  String get publicMusicVisibilityTitle => 'Müzik Zevkimi profilimde göster';

  @override
  String get publicMusicVisibilityBody =>
      'Kapatırsan seçimin gizli kalır. Spotify bağlı kalır ve eşleşmelerini iyileştirmeye devam eder.';

  @override
  String get publicMusicHiddenNotice => 'Müzik Zevkin diğer kişilerden gizli.';

  @override
  String get publicMusicEditCta => 'Müzik Zevkimi düzenle';

  @override
  String get profileMusicTasteHeading => 'Müzik zevki';

  @override
  String get profileMusicOpenInSpotify => 'Spotify\'da aç';

  @override
  String get musicLimitedData =>
      'Spotify bağlı, ancak henüz fazla dinleme geçmişi yok.';

  @override
  String get humorCalibrationIntroTitle => 'Neye güldüğünü öğrenelim';

  @override
  String get humorCalibrationIntroBody =>
      'Birkaç kısa içeriğe tepki ver. Verdiğin tepkiler mizah zevkini anlamamıza yardımcı olur; böylece eşleşmelerinle ortak mizahınızı sana gösterebiliriz.';

  @override
  String humorCalibrationIntroMeta(int count) {
    return '$count kısa içerik · yaklaşık 1 dakika';
  }

  @override
  String get humorCalibrationPausedTitle => 'Bugünlük bu kadar';

  @override
  String get humorCalibrationPausedBody =>
      'Bir içerik oynatılamadı. Kalanı yarın seni bekliyor; mizah profilin o zaman tamamlanacak.';

  @override
  String get humorLabCalibratedBody =>
      'Bundan sonra her gün birkaç yeni içerikle devam ediyoruz.';

  @override
  String get humorCalibrationStart => 'Başla';

  @override
  String get humorCalibrationSkip => 'Şimdilik geç';

  @override
  String get humorCalibrationResume => 'Devam et';

  @override
  String humorCalibrationProgress(int completed, int total) {
    return '$completed / $total';
  }

  @override
  String get humorCalibrationHintEarly => 'Seni biraz tanıyoruz…';

  @override
  String get humorCalibrationHintMiddle => 'Mizah tarzın şekillenmeye başladı.';

  @override
  String get humorCalibrationHintFinal => 'Son birkaç tane.';

  @override
  String get humorCalibrationResumeNote => 'Kaldığın yerden devam ediyorsun.';

  @override
  String get humorCalibrationCatalogGap =>
      'Şu an yeterli içerik yok. Daha sonra tekrar dene.';

  @override
  String get humorProfileEntryNotStarted => 'Neye güldüğünü öğrenelim';

  @override
  String humorProfileEntryInProgress(int completed, int total) {
    return '$completed / $total tamamlandı';
  }

  @override
  String get humorProfileEntryComplete => 'Mizah profilin hazır';

  @override
  String get humorFeedAllCaughtUp =>
      'Şimdilik hepsi bu. Yeni içerikler eklendikçe burada olacak.';

  @override
  String get humorFeedNoContent => 'Şu an gösterilecek içerik yok.';

  @override
  String get humorResultTitle => 'Mizah profilin hazır';

  @override
  String get humorResultSubtitle => 'Seni biraz tanıdık. İşte öne çıkanlar.';

  @override
  String humorResultSummaryTwo(String first, String second) {
    return '$first ve $second seni yakalıyor.';
  }

  @override
  String humorResultSummaryOne(String first) {
    return 'Özellikle $first sana göre.';
  }

  @override
  String get humorResultSummaryNone =>
      'Mizah tarzın henüz net değil; keşfettikçe netleşecek.';

  @override
  String humorResultContrast(String weakest) {
    return '$weakest ise pek işlemiyor.';
  }

  @override
  String get humorResultDone => 'Devam et';

  @override
  String get humorResultEvolvesNote =>
      'Yeni içeriklere tepki verdikçe profilin gelişmeye devam eder.';

  @override
  String get humorResultStrengthHigh => 'Güçlü';

  @override
  String get humorResultStrengthMedium => 'Belirgin';

  @override
  String get humorResultStrengthLow => 'Hafif';

  @override
  String get musicTasteGeneralHeading => 'Genel olarak dinlediği';

  @override
  String musicTasteDominant(String genres) {
    return 'Ağırlıklı olarak $genres çevresinde.';
  }

  @override
  String musicTasteSignature(String artists) {
    return 'Dönüp dolaşıp $artists dinliyor.';
  }

  @override
  String musicTasteStable(int count) {
    return 'Aylardır bırakmadığı $count sanatçı.';
  }

  @override
  String get humorSaved => 'Kaydedildi';

  @override
  String get premiumTitle => 'Mevora Premium';

  @override
  String get premiumSubtitle => 'Seni kimlerin beğendiğini gör, dahası da var.';

  @override
  String get premiumSubscribeCta => 'Abone ol';

  @override
  String get premiumRestoreCta => 'Satın alımları geri yükle';

  @override
  String get premiumLoadingPlans => 'Planlar yükleniyor…';

  @override
  String get premiumUnavailableTitle => 'Premium şu anda kullanılamıyor';

  @override
  String get premiumUnavailableBody =>
      'Planlar mağazadan yüklenemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get premiumPurchasing => 'Mağaza bekleniyor…';

  @override
  String get premiumVerifying => 'Satın alman kontrol ediliyor…';

  @override
  String get premiumRestoring => 'Geri yükleniyor…';

  @override
  String get premiumPurchasedTitle => 'Premium oldun';

  @override
  String get premiumPurchasedBody => 'Aboneliğin aktif. İyi kullanımlar.';

  @override
  String get premiumCancelled => 'Satın alma iptal edildi.';

  @override
  String get premiumFailed => 'Satın alma tamamlanamadı.';

  @override
  String get premiumRejected => 'Bu satın almayı doğrulayamadık.';

  @override
  String get premiumNothingToRestore =>
      'Bu mağaza hesabı için önceki bir satın alma bulunamadı.';

  @override
  String get premiumStoreUnavailable => 'Mağaza bu cihazda kullanılamıyor.';

  @override
  String get premiumAlreadyActive => 'Zaten Premium üyesin.';

  @override
  String get premiumRetry => 'Tekrar dene';

  @override
  String get premiumRenewsLabel =>
      'Otomatik yenilenir. İstediğin zaman mağazadan iptal edebilirsin.';

  @override
  String get premiumPlanBilledMonthly => 'Aylık faturalanır';

  @override
  String get premiumPlanBilledYearly => 'Yıllık faturalanır';

  @override
  String premiumPricePerMonth(String price) {
    return '$price / ay';
  }

  @override
  String premiumPricePerYear(String price) {
    return '$price / yıl';
  }

  @override
  String premiumRenewalMonthly(String price) {
    return 'Aboneliğin, sen iptal edene kadar her ay $price üzerinden otomatik yenilenir.';
  }

  @override
  String premiumRenewalYearly(String price) {
    return 'Aboneliğin, sen iptal edene kadar her yıl $price üzerinden otomatik yenilenir.';
  }

  @override
  String premiumRenewalGeneric(String price) {
    return 'Aboneliğin, sen iptal edene kadar her fatura döneminde $price üzerinden otomatik yenilenir.';
  }

  @override
  String premiumCancelHow(String store) {
    return 'İstediğin zaman $store > Abonelikler bölümünden iptal edebilirsin. Ödediğin dönemin sonuna kadar Premium açık kalır.';
  }

  @override
  String get premiumManageSubscription => 'Aboneliği yönet';

  @override
  String premiumManageSubscriptionFailed(String store) {
    return '$store açılamadı. Aboneliğini yönetmek için $store > Abonelikler bölümüne git.';
  }

  @override
  String get musicFollowedArtistsTitle => 'Takip ettiğin sanatçılar';

  @override
  String get musicTopArtistsTitle => 'En çok dinlediğin sanatçılar';

  @override
  String get musicTopTracksTitle => 'En çok dinlediğin parçalar';

  @override
  String get musicPlaylistsTitle => 'Playlistlerin';

  @override
  String get musicFollowedArtistsReconnect =>
      'Takip ettiğin sanatçıları göstermek için Spotify\'ı yeniden bağla.';

  @override
  String musicPlaylistTrackCount(int count) {
    return '$count parça';
  }

  @override
  String get musicSectionEmpty => 'Burada henüz bir şey yok.';

  @override
  String get profileSectionSignals => 'Uyum sinyallerin';

  @override
  String get profileSectionTrust => 'Güven ve görünürlük';

  @override
  String get premiumBenefitsHeading => 'Premium ile neler açılır';

  @override
  String get premiumBenefitLikesTitle => 'Seni kimlerin beğendiğini gör';

  @override
  String get premiumBenefitLikesBody =>
      'Seni beğenen herkes tek listede — ve neden uyumlu olabileceğiniz.';

  @override
  String get premiumBenefitMusicTitle => 'Müzik uyumunun tamamı';

  @override
  String get premiumBenefitMusicBody =>
      'Her eşleşmenle paylaştığın şarkılar, sanatçılar ve türler.';

  @override
  String get premiumPlansHeading => 'Planını seç';

  @override
  String get chatPreviewEncrypted => 'Şifreli mesaj';

  @override
  String get streakTitle => 'Günlük Seri';

  @override
  String get streakIndicatorTooltip => 'Günlük serin';

  @override
  String streakIndicatorSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Günlük seri: $count gün',
      one: 'Günlük seri: 1 gün',
    );
    return '$_temp0';
  }

  @override
  String streakDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count günlük seri',
      one: '1 günlük seri',
    );
    return '$_temp0';
  }

  @override
  String streakDetailsBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gündür Mevora\'ya her gün dönüyorsun.',
      one: 'Bugün Mevora\'ya geldin. Yarın da gelirsen serin büyür.',
    );
    return '$_temp0';
  }

  @override
  String streakLongest(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'En uzun serin: $count gün',
      one: 'En uzun serin: 1 gün',
    );
    return '$_temp0';
  }

  @override
  String streakTotalDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mevora\'da toplam $count gün',
      one: 'Mevora\'da toplam 1 gün',
    );
    return '$_temp0';
  }

  @override
  String get streakLastSevenDays => 'Son 7 gün';

  @override
  String streakWeekSemantics(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Son 7 günün $count gününde Mevora\'ya döndün',
      one: 'Son 7 günün 1 gününde Mevora\'ya döndün',
    );
    return '$_temp0';
  }

  @override
  String get streakHowItWorks =>
      'Serin, Mevora\'ya döndüğün her gün bir artar. Aynı gün uygulamayı yeniden açmak seriyi artırmaz.';

  @override
  String get streakMissedDayNote =>
      'Bir gün ara verirsen yeni bir seri başlar. En uzun serin her zaman kayıtlı kalır.';

  @override
  String get streakStartedTitle => 'Serin başladı';

  @override
  String get streakStartedBody =>
      'Bugün Mevora\'ya geldin. Yarın devam edebilirsin.';

  @override
  String get streakContinuedBody => 'Serini bugün de sürdürdün.';

  @override
  String get streakRestartedTitle => 'Yeni bir seri başladı';

  @override
  String get streakRestartedBody =>
      'Bugün yeniden 1. gündesin. En uzun serin kayıtlı kalıyor.';

  @override
  String get streakPersonalBest => 'Yeni kişisel rekor';

  @override
  String get streakMilestone => 'Dönüm noktası';

  @override
  String get streakCelebrationDismiss => 'Devam et';

  @override
  String get onboardingSmokingVapeOnly => 'Sadece elektronik sigara';

  @override
  String get onboardingSmokingQuitting => 'Bırakmaya çalışıyorum';

  @override
  String get onboardingAlcoholSober => 'Alkolü bıraktım';

  @override
  String get onboardingExerciseAthlete => 'Çok aktif / sporcu';

  @override
  String get onboardingLifestyleBird => 'Kuş';

  @override
  String get onboardingLifestyleFish => 'Balık';

  @override
  String get onboardingPetsWant => 'Yok ama istiyorum';

  @override
  String get onboardingPetsAllergic => 'Alerjim var';

  @override
  String get onboardingDiet => 'Beslenme';

  @override
  String get dietOmnivore => 'Her şeyi yerim';

  @override
  String get dietVegetarian => 'Vejetaryen';

  @override
  String get dietVegan => 'Vegan';

  @override
  String get dietPescatarian => 'Pesketaryen';

  @override
  String get dietHalal => 'Helal';

  @override
  String get dietGlutenFree => 'Glütensiz';

  @override
  String get onboardingAboutYouSubtitle =>
      'İsteğe bağlı. İstediklerini cevapla; sana seçtiklerimizi daha isabetli yapar.';

  @override
  String get sharedTraitsTitle => 'Ortak noktalarınız';

  @override
  String get sharedTraitGoal => 'Aradığınız';

  @override
  String get sharedTraitQuestions => 'İlişki soruları';

  @override
  String sharedTraitQuestionsValue(int aligned, int shared) {
    return '$shared sorunun $aligned tanesinde aynı cevap';
  }

  @override
  String get sharedTraitChildren => 'Çocuk';

  @override
  String get sharedTraitAge => 'Yaş';

  @override
  String sharedTraitAgeValue(int mine, int theirs) {
    return '$mine ve $theirs, yaşlarınız yakın';
  }

  @override
  String get sharedTraitExpectations => 'Sigara ve alkol beklentisi';

  @override
  String get sharedTraitExpectationsValue =>
      'Birbirinizin beklentisine uyuyorsunuz';

  @override
  String get sharedTraitRhythm => 'Günlük ritim';

  @override
  String get sharedTraitHobbies => 'Hobiler';

  @override
  String get sharedTraitLanguages => 'Diller';

  @override
  String get humorDailyTitle => 'Bugünün Mizah Turu 🎭';

  @override
  String get humorDailyBody =>
      'Her gün birkaç kısa video ile seni biraz daha iyi tanıyoruz.';

  @override
  String get humorDailySecondary =>
      'Neye güldüğünü öğrendikçe Mevora seni daha iyi tanır.';

  @override
  String humorDailyMeta(int count) {
    return '$count kısa video';
  }

  @override
  String get humorDailyStart => 'Başla';

  @override
  String humorDailyResume(int answered, int total) {
    return 'Devam et · $answered/$total';
  }

  @override
  String get humorDailyDone => 'Bugünlük tamam ✓';

  @override
  String get humorDailyLater => 'Sonra';

  @override
  String get humorDailyStartsTomorrow => 'Günlük mizah turun yarın başlıyor.';

  @override
  String humorDailyProgress(int position, int total) {
    return '$position/$total';
  }

  @override
  String get humorDailyHintStart => 'Bugünün mizah turuna başladık.';

  @override
  String get humorDailyHintMiddle => 'Biraz daha tanıyoruz 👀';

  @override
  String get humorDailyHintEnd => 'Neredeyse bitti.';

  @override
  String get humorDailyCompletedTitle => 'Bugünlük tamam 🎭';

  @override
  String get humorDailyCompletedBody => 'Mizah profilin biraz daha netleşti.';

  @override
  String get humorDailyCompletedTomorrow => 'Yarın yeni tur seni bekliyor.';

  @override
  String get humorDailySequenceComplete =>
      'Şimdilik tüm içerikleri tamamladın. Yenileri eklendiğinde tur devam edecek.';

  @override
  String get humorDailyNotReadyTitle => 'Bugünün turu hazırlanıyor';

  @override
  String get humorDailyNotReadyBody => 'Biraz sonra yeniden bakabilirsin.';

  @override
  String get humorDailyLockedBody =>
      'Günlük mizah turu, mizah profilin hazır olduğunda başlar.';

  @override
  String get appOpsMaintenanceTitle => 'Kısa bir bakım molası';

  @override
  String get appOpsMaintenanceMessage =>
      'Mevora kısa süreli bakımda. Birazdan tekrar buradayız.';

  @override
  String get appOpsMaintenanceSupport => 'Destekle iletişime geç';

  @override
  String get appOpsMaintenanceAccount => 'Hesap ayarları';

  @override
  String get appOpsUpdateRequiredTitle => 'Güncelleme zamanı';

  @override
  String get appOpsUpdateRequiredMessage =>
      'Mevora\'nın bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı güncelle.';

  @override
  String get appOpsUpdateAction => 'Güncelle';

  @override
  String appOpsUpdateFromStore(String store) {
    return 'Mevora\'yı $store üzerinden güncelle.';
  }

  @override
  String get appOpsGenericStore => 'uygulama mağazası';

  @override
  String get appOpsUpdateAvailable => 'Mevora\'nın yeni bir sürümü hazır.';

  @override
  String get appOpsFeatureUnavailableTitle => 'Geçici olarak kullanılamıyor';

  @override
  String get appOpsFeatureUnavailableMessage =>
      'Bu özellik kısa bir mola verdi. Biraz sonra yeniden bakabilirsin.';

  @override
  String get appOpsSpotifyUnavailable =>
      'Spotify bağlantısı şu an geçici olarak kullanılamıyor. Daha sonra Müzik sekmesinden bağlayabilirsin.';

  @override
  String get supportTicketRepliesTitle => 'Yanıtlar';

  @override
  String get supportTicketNoRepliesYet =>
      'Henüz yanıt yok. Mevora Destek sana buradan yanıt verecek.';

  @override
  String get supportTicketRepliesError =>
      'Yanıtlar yüklenemedi. Daha sonra tekrar dene.';

  @override
  String get supportTicketDefaultAuthor => 'Mevora Destek';

  @override
  String get supportTicketRepliedBadge => 'Destek yanıtladı';

  @override
  String get supportTicketNoComposerHint =>
      'Eklemek istediğin bir şey mi var? Yeni bir talep gönder ve bu talepten bahset.';

  @override
  String get accountRestrictedTitle => 'Hesap kısıtlandı';

  @override
  String get accountRestrictedHeadline => 'Hesabın kısıtlandı';

  @override
  String get accountRestrictedBody =>
      'Hesabın kısıtlıyken Keşfet, eşleşmeler ve sohbeti kullanamazsın. Yine de nedenini görebilir, karara itiraz edebilir, destekle iletişime geçebilir ya da verilerini yönetebilirsin.';

  @override
  String accountRestrictedUntil(String date) {
    return 'Kısıtlama $date tarihinde sona erer.';
  }

  @override
  String get accountRestrictedOpenEnded =>
      'Kısıtlama, ekibimiz inceleyene kadar devam eder.';

  @override
  String get accountRestrictedReleaseNote =>
      'Kısıtlama kaldırıldığında otomatik olarak Mevora\'ya geri döneceksin.';

  @override
  String get accountRestrictedWhy => 'Hesabım neden kısıtlandı?';

  @override
  String get accountRestrictedContactSupport => 'Destekle iletişime geç';

  @override
  String get accountRestrictedManageData => 'Verilerin ve hesap silme';

  @override
  String get moderationStatusTitle => 'Hesap durumu';

  @override
  String get moderationStatusSettingsSubtitle =>
      'Uyarılar, kısıtlamalar ve itirazlar';

  @override
  String get moderationStatusActive => 'Hesabın iyi durumda.';

  @override
  String get moderationStatusSuspended => 'Hesabın kısıtlandı.';

  @override
  String get moderationStatusBanned => 'Hesabın kapatıldı.';

  @override
  String get moderationStatusInactive => 'Hesabın aktif değil.';

  @override
  String moderationStatusReason(String category) {
    return 'Neden: $category';
  }

  @override
  String get moderationStatusLoadFailed =>
      'Hesap durumun yüklenemedi. Tekrar denemek için aşağı çek.';

  @override
  String get moderationDecisionsTitle => 'Hesabınla ilgili kararlar';

  @override
  String get moderationDecisionsEmpty =>
      'Hesabınla ilgili bir moderasyon kararı yok.';

  @override
  String moderationDecisionUntil(String date) {
    return '$date tarihine kadar';
  }

  @override
  String get moderationDecisionReversed => 'Geri alındı';

  @override
  String get moderationTypeWarning => 'Uyarı';

  @override
  String get moderationTypeTemporarySuspension => 'Geçici kısıtlama';

  @override
  String get moderationTypePermanentBan => 'Hesap kapatma';

  @override
  String get moderationTypePhotoRejected => 'Fotoğraf onaylanmadı';

  @override
  String get moderationTypePhotoRemoved => 'Fotoğraf kaldırıldı';

  @override
  String get moderationTypeRequireReverification => 'Yeniden doğrulama gerekli';

  @override
  String get moderationTypeOther => 'Moderasyon kararı';

  @override
  String get moderationReasonHarmfulBehavior =>
      'Zarar verici ya da taciz edici davranış';

  @override
  String get moderationReasonScamOrFraud => 'Dolandırıcılık';

  @override
  String get moderationReasonSpam => 'İstenmeyen içerik (spam)';

  @override
  String get moderationReasonAuthenticity => 'Profil gerçekliği';

  @override
  String get moderationReasonAgeRequirement => 'Yaş şartı';

  @override
  String get moderationReasonContentRules => 'İçerik kuralları';

  @override
  String get moderationReasonPhotoRequirements => 'Fotoğraf şartları';

  @override
  String get moderationReasonWellbeing => 'Güvenlik ve iyi oluş';

  @override
  String get moderationReasonGeneral => 'Topluluk kuralları';

  @override
  String get moderationAppealAction => 'Bu karara itiraz et';

  @override
  String get moderationAppealOpen =>
      'İtirazın alındı. İnceleyip sonucu burada göstereceğiz.';

  @override
  String get moderationAppealInReview => 'İtirazın inceleniyor.';

  @override
  String get moderationAppealAccepted => 'İtirazın kabul edildi';

  @override
  String get moderationAppealRejected => 'İtirazın kabul edilmedi';

  @override
  String get moderationAppealResolved => 'İtirazın incelendi';

  @override
  String get moderationAppealWindowClosed =>
      'Bu karar için 30 günlük itiraz süresi doldu.';

  @override
  String get moderationAppealSheetBody =>
      'Bu kararın neden yanlış olduğunu düşündüğünü anlat. Kararı vermeyen bir ekip üyemiz inceleyecek.';

  @override
  String get moderationAppealReasonLabel => 'İtirazın';

  @override
  String get moderationAppealReasonHint => 'En az 10 karakter';

  @override
  String get moderationAppealReasonTooShort => 'Lütfen en az 10 karakter yaz.';

  @override
  String get moderationAppealSubmit => 'İtirazı gönder';

  @override
  String get moderationAppealSent =>
      'İtirazın gönderildi. Sonucu burada göstereceğiz.';

  @override
  String get moderationAppealAlreadySent => 'Bu karara zaten itiraz ettin.';

  @override
  String get moderationAppealNotAllowed => 'Bu karara itiraz edilemez.';

  @override
  String get moderationAppealInvalid =>
      'Lütfen 10 ile 2.000 karakter arasında yaz.';

  @override
  String get moderationAppealFailed =>
      'İtirazın gönderilemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get faceAnchorRequiredNotice =>
      'Devam etmek için yüzünün net göründüğü bir fotoğrafını doğrula.';

  @override
  String get faceAnchorVerifyAction => 'Fotoğrafını doğrula';

  @override
  String get faceAnchorVerifyShort => 'Doğrula';

  @override
  String get faceAnchorVerified => 'Bu fotoğraf doğrulandı';

  @override
  String get faceAnchorVerifiedShort => 'Doğrulandı';

  @override
  String get faceAnchorPending => 'Doğrulama bekleniyor';

  @override
  String get faceAnchorPhotoInReview => 'Fotoğraf inceleniyor';

  @override
  String get faceAnchorNotVerified => 'Doğrulanamadı';

  @override
  String get faceAnchorRetry => 'Tekrar dene';

  @override
  String get faceAnchorMismatch => 'Bu fotoğraf çektiğin selfie ile eşleşmedi.';

  @override
  String get faceAnchorLivenessFailed =>
      'Canlılık doğrulaması tamamlanamadı. Aydınlık bir yerde, doğrudan kameraya bakarak tekrar dene.';

  @override
  String get faceAnchorPhotoUnclear =>
      'Bu fotoğrafta yüzün tek başına ve net görünmüyor. Yalnızca senin göründüğün bir fotoğraf seç.';

  @override
  String get faceAnchorSelfieInvalid =>
      'Selfie kullanılamadı. Kameranla yeni bir selfie çekip tekrar dene.';

  @override
  String get faceAnchorTechnicalError =>
      'Doğrulama şu anda tamamlanamadı. Fotoğrafın doğrulanmadı; biraz sonra tekrar dene.';

  @override
  String get faceAnchorPrimaryRequiresVerify =>
      'Bu fotoğrafı ana fotoğraf yapmak için önce doğrula.';

  @override
  String get faceAnchorLastAnchorDelete =>
      'Son doğrulanmış fotoğrafını silemezsin. Önce başka bir fotoğrafını doğrula.';

  @override
  String get faceAnchorExplainBody =>
      'Fotoğrafının gerçekten sana ait olduğundan emin olmak için kısa bir selfie kontrolü yapıyoruz.';

  @override
  String get faceAnchorExplainSteps =>
      'Ön kameranla bir selfie çekeceksin. Selfie yalnızca bu kontrol için kullanılır, profilinde görünmez ve kontrol bitince silinir.';

  @override
  String get faceAnchorConsent =>
      'Selfiemin bu fotoğrafla karşılaştırılması için işlenmesini kabul ediyorum.';

  @override
  String get faceAnchorTakeSelfie => 'Selfie çek';

  @override
  String get faceAnchorOpening => 'Hazırlanıyor…';

  @override
  String get faceAnchorCapturing => 'Kamera açılıyor…';

  @override
  String get faceAnchorUploading => 'Selfie gönderiliyor…';

  @override
  String get faceAnchorVerifying => 'Doğrulanıyor…';

  @override
  String get faceAnchorSuccessBody =>
      'Bu fotoğraf artık ana fotoğrafın olabilir.';

  @override
  String get faceAnchorDone => 'Tamam';

  @override
  String get faceAnchorChooseAnother => 'Başka fotoğraf seç';

  @override
  String get faceAnchorPromptBody =>
      'Profilinin gerçekten sana ait olduğunu göstermek için yüzünün net göründüğü bir fotoğrafını doğrula.';

  @override
  String get faceAnchorProfileVerifiedTitle => 'Profil fotoğrafın doğrulandı';

  @override
  String get faceAnchorPromptTileSubtitle =>
      'Yüzünün göründüğü bir fotoğrafı kısa bir selfie ile doğrula';

  @override
  String get faceAnchorErrorUnavailable =>
      'Fotoğraf doğrulama şu anda kullanılamıyor. Lütfen daha sonra tekrar dene.';

  @override
  String get faceAnchorErrorPhotoNotApproved =>
      'Bu fotoğraf hâlâ inceleniyor. İnceleme bitince doğrulayabilirsin.';

  @override
  String get faceAnchorErrorCooldown => 'Biraz bekleyip tekrar dene.';

  @override
  String get faceAnchorErrorAttemptLimit =>
      'Bugünlük deneme hakkın doldu. Yarın tekrar deneyebilirsin.';

  @override
  String get faceAnchorErrorCamera =>
      'Kamera açılamadı. Kamera iznini kontrol edip tekrar dene.';

  @override
  String get faceAnchorErrorUpload =>
      'Selfie gönderilemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get faceAnchorErrorInProgress =>
      'Bir doğrulama zaten sürüyor. Lütfen sonucu bekle.';

  @override
  String get faceAnchorErrorConsent =>
      'Devam etmek için onay vermen gerekiyor.';

  @override
  String get faceAnchorErrorGeneric =>
      'Doğrulama başlatılamadı. Lütfen tekrar dene.';
}
