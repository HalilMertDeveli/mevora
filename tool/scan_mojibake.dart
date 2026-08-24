import 'dart:convert';
import 'dart:io';

void main() {
  final roots = [
    Directory(r'D:\Mevora\lib'),
    Directory(r'D:\Mevora\hosting'),
    Directory(r'D:\Mevora\tool'),
  ];
  final patterns = [
    'Ã§',
    'Ã¶',
    'Ã¼',
    'ÄŸ',
    'Ä±',
    'ÅŸ',
    'Ä°',
    'Ã‡',
    'Ã–',
    'Ãœ',
    'â€”',
    'â€¦',
    'â€™',
    'â€œ',
    'â€',
  ];
  final hits = <String>[];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File) continue;
      final path = entity.path;
      if (!(path.endsWith('.dart') ||
          path.endsWith('.arb') ||
          path.endsWith('.json') ||
          path.endsWith('.yaml') ||
          path.endsWith('.yml') ||
          path.endsWith('.xml') ||
          path.endsWith('.html') ||
          path.endsWith('.md'))) {
        continue;
      }
      if (path.contains(r'\.dart_tool\') || path.contains(r'\build\')) {
        continue;
      }
      late String text;
      try {
        text = utf8.decode(entity.readAsBytesSync(), allowMalformed: true);
      } on Object {
        continue;
      }
      for (final p in patterns) {
        if (text.contains(p)) {
          hits.add('$path :: $p');
          break;
        }
      }
    }
  }
  if (hits.isEmpty) {
    print('NO_MOJIBAKE_FOUND');
  } else {
    print('MOJIBAKE_HITS=${hits.length}');
    for (final h in hits.take(80)) {
      print(h);
    }
  }
}
