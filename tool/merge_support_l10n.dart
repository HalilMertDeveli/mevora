import 'dart:convert';
import 'dart:io';

/// Merges support l10n JSON into ARB files using strict UTF-8 (no PowerShell).
void main() {
  _merge(
    arbPath: r'D:\Mevora\lib\l10n\app_en.arb',
    jsonPath: r'D:\Mevora\tool\support_l10n_en.json',
  );
  _merge(
    arbPath: r'D:\Mevora\lib\l10n\app_tr.arb',
    jsonPath: r'D:\Mevora\tool\support_l10n_tr.json',
  );
  print('Merged support keys into ARB files (UTF-8).');
}

void _merge({required String arbPath, required String jsonPath}) {
  final arbFile = File(arbPath);
  final jsonFile = File(jsonPath);
  final arb =
      jsonDecode(utf8.decode(arbFile.readAsBytesSync())) as Map<String, dynamic>;
  final extra =
      jsonDecode(utf8.decode(jsonFile.readAsBytesSync())) as Map<String, dynamic>;
  for (final entry in extra.entries) {
    arb[entry.key] = entry.value;
  }
  final encoder = JsonEncoder.withIndent('  ');
  final out = '${encoder.convert(arb)}\n';
  arbFile.writeAsBytesSync(utf8.encode(out));
  print(
    '$arbPath keys=${arb.length} hasİ=${out.contains('İ')} hasş=${out.contains('ş')}',
  );
}
