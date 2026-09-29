import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/matching/domain/models/match.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';

final _en = lookupAppLocalizations(const Locale('en'));

Widget _tile(String lastMessage) {
  final match = Match(
    id: 'a_b',
    userIds: const ['a', 'b'],
    createdAt: DateTime(2026, 3, 1),
    isActive: true,
    lastMessage: lastMessage,
  );
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: MatchConnectionTile(
        item: MatchListItem(match: match, otherUserId: 'b', name: 'Elif'),
        currentUid: 'a',
      ),
    ),
  );
}

void main() {
  for (final (sentinel, label, icon) in [
    ('🔒', _en.chatPreviewEncrypted, MevoraIcons.lock),
    ('📷', _en.attachPhoto, MevoraIcons.photo),
    ('🎤', _en.recordVoice, MevoraIcons.mic),
  ]) {
    testWidgets('the $sentinel preview reads as "$label", not an emoji', (
      tester,
    ) async {
      await tester.pumpWidget(_tile(sentinel));

      expect(find.text(label), findsOneWidget);
      expect(find.byIcon(icon), findsOneWidget);
      expect(find.text(sentinel), findsNothing);
    });
  }

  testWidgets('a plain text preview is shown as written', (tester) async {
    await tester.pumpWidget(_tile('See you at eight'));
    expect(find.text('See you at eight'), findsOneWidget);
  });
}
