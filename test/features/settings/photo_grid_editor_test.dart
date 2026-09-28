import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/presentation/widgets/photo_grid_editor.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

const _photos = [
  ProfilePhoto(id: 'b', storagePath: 'p/b', order: 1),
  ProfilePhoto(id: 'a', storagePath: 'p/a', isPrimary: true),
  ProfilePhoto(id: 'c', storagePath: 'p/c', order: 2),
];

Widget _editor({
  List<ProfilePhoto> photos = _photos,
  ValueChanged<String>? onSetPrimary,
  ValueChanged<String>? onDelete,
  VoidCallback? onAdd,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: SingleChildScrollView(
        child: PhotoGridEditor(
          photos: photos,
          onAdd: onAdd ?? () {},
          onDelete: onDelete ?? (_) {},
          onReorder: (_, _) {},
          onSetPrimary: onSetPrimary ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('rows are labelled by position, the main photo first', (
    tester,
  ) async {
    await tester.pumpWidget(_editor());

    expect(find.text(_en.onboardingPrimaryPhoto), findsOneWidget);
    expect(find.text(_en.onboardingPhotoNumber(2)), findsOneWidget);
    expect(find.text(_en.onboardingPhotoNumber(3)), findsOneWidget);
    // The page owns the section heading; the editor must not repeat it.
    expect(find.text(_en.photos), findsNothing);
    expect(
      tester.getTopLeft(find.text(_en.onboardingPrimaryPhoto)).dy,
      lessThan(tester.getTopLeft(find.text(_en.onboardingPhotoNumber(2))).dy),
    );
  });

  testWidgets('the menu makes a photo the main one', (tester) async {
    String? primary;
    await tester.pumpWidget(_editor(onSetPrimary: (id) => primary = id));

    await tester.tap(find.byTooltip(_en.more).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.settingsSetPrimaryPhoto));
    await tester.pumpAndSettle();

    expect(primary, 'b');
  });

  testWidgets('the main photo cannot be made main again, only removed', (
    tester,
  ) async {
    String? deleted;
    await tester.pumpWidget(_editor(onDelete: (id) => deleted = id));

    await tester.tap(find.byTooltip(_en.more).first);
    await tester.pumpAndSettle();
    expect(find.text(_en.settingsSetPrimaryPhoto), findsNothing);
    await tester.tap(find.text(_en.settingsDeletePhoto));
    await tester.pumpAndSettle();

    expect(deleted, 'a');
  });

  testWidgets('the add row disappears at the photo limit', (tester) async {
    await tester.pumpWidget(_editor());
    expect(find.byIcon(MevoraIcons.addPhoto), findsOneWidget);

    await tester.pumpWidget(
      _editor(
        photos: [
          for (var i = 0; i < 6; i++)
            ProfilePhoto(id: '$i', storagePath: 'p/$i', order: i),
        ],
      ),
    );
    expect(find.byIcon(MevoraIcons.addPhoto), findsNothing);
  });
}
