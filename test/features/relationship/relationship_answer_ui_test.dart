import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

void main() {
  testWidgets('short answer labels render fully without ellipsis', (tester) async {
    final question = RelationshipQuestionCatalog.byId('rq_001')!;
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RelationshipQuestionCard(
            question: question,
            answeredCount: 1,
            totalCount: 3,
            onAnswer: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final answer in question.answers) {
      expect(find.text(answer.labelTr), findsOneWidget);
    }

    final buttons = tester.widgetList<MevoraButton>(find.byType(MevoraButton));
    expect(buttons.where((b) => b.wrapLabel).length, greaterThanOrEqualTo(3));
  });

  testWidgets('narrow phone shows full Turkish answer text', (tester) async {
    final question = RelationshipQuestionCatalog.byId('rq_004')!;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: RelationshipQuestionCard(
            question: question,
            answeredCount: 2,
            totalCount: 3,
            onAnswer: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('mesaj'), findsWidgets);
    expect(find.text('Sen'), findsNothing);
    expect(find.text('Ben'), findsNothing);
  });
}
