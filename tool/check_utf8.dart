import 'dart:convert';
import 'dart:io';

void main() {
  final files = [
    r'D:\Mevora\lib\l10n\app_tr.arb',
    r'D:\Mevora\lib\l10n\app_en.arb',
    r'D:\Mevora\tool\support_l10n_tr.json',
    r'D:\Mevora\tool\support_l10n_en.json',
    r'D:\Mevora\lib\l10n\app_localizations_tr.dart',
  ];
  for (final path in files) {
    final f = File(path);
    if (!f.existsSync()) {
      print('MISSING $path');
      continue;
    }
    final bytes = f.readAsBytesSync();
    final text = utf8.decode(bytes, allowMalformed: true);
    final checks = {
      'ı': text.contains('ı'),
      'İ': text.contains('İ'),
      'ğ': text.contains('ğ'),
      'ş': text.contains('ş'),
      'ç': text.contains('ç'),
      'ö': text.contains('ö'),
      'ü': text.contains('ü'),
      'mojibake_Ã§': text.contains('Ã§'),
      'mojibake_Ä±': text.contains('Ä±'),
      'mojibake_ÅŸ': text.contains('ÅŸ'),
    };
    print('$path');
    print('  size=${bytes.length} bom=${bytes.length >= 3 && bytes[0] == 0xEF}');
    print('  $checks');
  }
}
