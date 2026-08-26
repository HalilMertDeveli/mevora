/// User-facing photo upload copy. Never expose raw Firebase Storage codes.
abstract final class PhotoUploadMessages {
  static const String needSignIn = 'Fotoğraf yüklemek için giriş yapmalısın.';
  static const String failed =
      'Fotoğraf yüklenirken bir hata oluştu. Lütfen tekrar deneyin.';
  static const String timeout =
      'Fotoğraf yüklenirken bir hata oluştu. Lütfen tekrar deneyin.';
  static const String minRequired = 'En az 3 fotoğraf eklemelisin.';
  static const String keepMin = 'Profilinde en az 3 fotoğraf bulunmalı.';
  static const String invalidFile = 'Bu fotoğraf türü veya boyutu uygun değil.';
}
