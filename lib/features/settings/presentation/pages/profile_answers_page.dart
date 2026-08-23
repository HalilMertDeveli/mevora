import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileAnswersPage extends StatefulWidget {
  const ProfileAnswersPage({super.key});

  @override
  State<ProfileAnswersPage> createState() => _ProfileAnswersPageState();
}

class _ProfileAnswersPageState extends State<ProfileAnswersPage> {
  Map<String, String> _answers = const {};
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final uid = AuthScope.of(context).user?.id;
    final repository = RelationshipScope.maybeOf(context);
    if (uid == null || repository == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    final result = await repository.getSavedAnswers(uid);
    if (mounted) {
      setState(() {
        _answers = result.valueOrNull ?? const {};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final relationship = RelationshipScope.maybeOf(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileAnswersTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: _answers.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.screenPadding),
                        child: Text(
                          l10n.profileAnswersEmpty,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      children: [
                        for (final entry in _answers.entries)
                          _AnswerEditor(
                            questionId: entry.key,
                            answerId: entry.value,
                            locale: locale,
                            onSave: relationship == null
                                ? null
                                : (answerId) => unawaited(
                                    _saveAnswer(
                                      relationship,
                                      entry.key,
                                      answerId,
                                    ),
                                  ),
                          ),
                      ],
                    ),
            ),
    );
  }

  Future<void> _saveAnswer(
    RelationshipRepository repository,
    String questionId,
    String answerId,
  ) async {
    final uid = AuthScope.of(context).user?.id;
    final settings = SettingsScope.maybeOf(context);
    final result = await repository.saveAnswer(
      questionId: questionId,
      answerId: answerId,
    );
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      setState(() => _answers = {..._answers, questionId: answerId});
      if (uid != null) {
        settings?.profileUpdates.notifyProfileUpdated(uid);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).settingsProfileSaved)),
      );
    }
  }
}

class _AnswerEditor extends StatelessWidget {
  const _AnswerEditor({
    required this.questionId,
    required this.answerId,
    required this.locale,
    this.onSave,
  });

  final String questionId;
  final String answerId;
  final String locale;
  final ValueChanged<String>? onSave;

  @override
  Widget build(BuildContext context) {
    final question = RelationshipQuestionCatalog.byId(questionId);
    if (question == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.promptFor(locale),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final option in question.answers)
                MevoraChip(
                  label: option.labelFor(locale),
                  selected: option.id == answerId,
                  onSelected: onSave == null
                      ? null
                      : (_) => onSave!(option.id),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
