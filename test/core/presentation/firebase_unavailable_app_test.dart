import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/presentation/pages/firebase_unavailable_app.dart';
import 'package:mevora/l10n/app_localizations.dart';

void main() {
  testWidgets('startup error app shows a user-safe message', (tester) async {
    await tester.pumpWidget(
      const MevoraStartupErrorApp(locale: Locale('en')),
    );

    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(find.text(l10n.somethingWentWrong), findsOneWidget);
    expect(find.text(l10n.firebaseUnavailableMessage), findsOneWidget);
    expect(find.textContaining('Firebase'), findsNothing);
    expect(find.textContaining('firebase'), findsNothing);
  });
}
