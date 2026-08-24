import "dart:io";
void main() {
  final tr = File("lib/l10n/app_localizations_tr.dart").readAsStringSync();
  for (final s in ["Yardım ve Destek","Gizlilik Politikası","Kullanım Koşulları","İstanbul","çağrı","Türkçe","hesabımı","eşleşme"]) {
    print("$s => ${tr.contains(s)}");
  }
  final en = File("lib/l10n/app_localizations_en.dart").readAsStringSync();
  print("EN emdash ok: ${en.contains('—') || en.contains('your first photo')}");
  print("EN mojibake: ${en.contains('â€')}");
}
