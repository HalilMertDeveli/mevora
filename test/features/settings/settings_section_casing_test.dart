import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/settings/presentation/widgets/settings_section.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _tr = lookupAppLocalizations(const Locale('tr'));
final _en = lookupAppLocalizations(const Locale('en'));

Widget _wrap(Widget child, Locale locale) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

void main() {
  testWidgets('Turkish section headers keep the dotted capital I', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        SettingsSection(
          title: _tr.notificationsTitle,
          children: const [SettingsNavTile(title: 'x')],
        ),
        const Locale('tr'),
      ),
    );

    // "Bildirimler ve gizlilik" -> "BİLDİRİMLER VE GİZLİLİK"
    expect(find.text('BİLDİRİMLER VE GİZLİLİK'), findsOneWidget);
    expect(
      find.text('BILDIRIMLER VE GIZLILIK'),
      findsNothing,
      reason: 'locale-insensitive toUpperCase leaked',
    );
  });

  testWidgets('Turkish dotless i uppercases to plain I in a header', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const SettingsSection(
          title: 'ışık',
          children: [SettingsNavTile(title: 'x')],
        ),
        const Locale('tr'),
      ),
    );

    expect(find.text('IŞIK'), findsOneWidget);
  });

  testWidgets('English section headers are unaffected', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SettingsSection(
          title: _en.notificationsTitle,
          children: const [SettingsNavTile(title: 'x')],
        ),
        const Locale('en'),
      ),
    );

    expect(find.text('NOTIFICATIONS AND PRIVACY'), findsOneWidget);
  });

  testWidgets('header styling is unchanged', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SettingsSection(
          title: 'account',
          children: [SettingsNavTile(title: 'x')],
        ),
        const Locale('en'),
      ),
    );

    final text = tester.widget<Text>(find.text('ACCOUNT'));
    expect(text.style?.letterSpacing, 1.4);
  });
}
