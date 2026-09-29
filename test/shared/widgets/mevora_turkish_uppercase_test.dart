import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

import '../../helpers/pump_app.dart';

/// Small-caps lines are uppercased for display. Dart's toUpperCase() maps
/// `i` to `I`, which is wrong in Turkish ("bildirimler" -> "BILDIRIMLER").
void main() {
  testWidgets('a Turkish eyebrow keeps the dotted capital İ', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraSectionHeader(title: 'Başlık', eyebrow: 'yeni eşleşme'),
        locale: const Locale('tr'),
      ),
    );
    expect(find.text('YENİ EŞLEŞME'), findsOneWidget);
    expect(find.text('YENI EŞLEŞME'), findsNothing);
  });

  testWidgets('an English eyebrow uppercases normally', (tester) async {
    await tester.pumpWidget(
      wrapWithApp(
        const MevoraSectionHeader(title: 'Title', eyebrow: 'why it fits'),
      ),
    );
    expect(find.text('WHY IT FITS'), findsOneWidget);
  });
}
