// Ensures chat AppBar uses peer profile name plumbing, not a hardcoded brand string.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chat_page AppBar title binds controller.otherName', () {
    final source = File(
      'lib/features/chat/presentation/pages/chat_page.dart',
    ).readAsStringSync();
    expect(source.contains('controller.otherName'), isTrue);
    expect(source.contains("Text('Mevora')"), isFalse);
    expect(source.contains('Text("Mevora")'), isFalse);
  });

  test('chat_controller otherName derives from match peer', () {
    final source = File(
      'lib/features/chat/presentation/controllers/chat_controller.dart',
    ).readAsStringSync();
    expect(source.contains('String get otherName'), isTrue);
    expect(source.contains('otherName(current)'), isTrue);
  });
}
