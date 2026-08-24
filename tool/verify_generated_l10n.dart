import 'dart:io';

void main() {
  for (final p in [
    'lib/l10n/app_localizations.dart',
    'lib/l10n/app_localizations_en.dart',
    'lib/l10n/app_localizations_tr.dart',
  ]) {
    final t = File(p).readAsStringSync();
    final bad = ['Ã§', 'Ä±', 'ÅŸ', 'ÄŸ', 'â€”', 'â€¦', 'â€™'];
    final hits = bad.where(t.contains).toList();
    print('$p bad=$hits');
  }
  final font = File('assets/fonts/Manrope-Regular.ttf');
  print('Manrope exists: ${font.existsSync()} size=${font.lengthSync()}');
}
