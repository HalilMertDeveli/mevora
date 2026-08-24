import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/domain/repositories/relationship_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class ProfileAnswersPage extends StatefulWidget {
  const ProfileAnswersPage({super.key});

  @override
  State<ProfileAnswersPage> createState() => _ProfileAnswersPageState();
}

class _ProfileAnswersPageState extends State<ProfileAnswersPage> {
  Map<String, String> _answers = const {};
  Map<String, ProfileQuestionAnswer> _profileAnswers = const {};
  StreamSubscription<List<ProfileQuestionAnswer>>? _profileSubscription;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final uid = AuthScope.of(context).user?.id;
    final repository = RelationshipScope.maybeOf(context);
    final profileAnswers = RelationshipScope.profileAnswersOf(context);
    if (uid == null || repository == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }
    unawaited(_profileSubscription?.cancel());
    if (profileAnswers != null) {
      _profileSubscription = profileAnswers.watchAnswers(uid).listen((items) {
        if (!mounted) {
          return;
        }
        setState(() {
          _profileAnswers = {for (final item in items) item.questionId: item};
        });
      });
      unawaited(profileAnswers.syncFromMatching());
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
    final profileAnswers = RelationshipScope.profileAnswersOf(context);
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
                          l10n.questionAnswersEmpty,
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
                            isVisible:
                                _profileAnswers[entry.key]?.isVisible ?? true,
                            onSave: relationship == null
                                ? null
                                : (answerId) => unawaited(
                                    _saveAnswer(
                                      relationship,
                                      entry.key,
                                      answerId,
                                    ),
                                  ),
                            onVisibilityChanged: profileAnswers == null
                                ? null
                                : (visible) => unawaited(
                                    _setVisibility(
                                      profileAnswers,
                                      entry.key,
                                      visible,
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
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final previous = _answers[questionId];
    setState(() => _answers = {..._answers, questionId: answerId});
    final result = await repository.saveAnswer(
      questionId: questionId,
      answerId: answerId,
    );
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      if (uid != null) {
        settings?.profileUpdates.notifyProfileUpdated(uid);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.settingsProfileSaved)),
      );
      return;
    }
    setState(() {
      if (previous == null) {
        final next = Map<String, String>.from(_answers)..remove(questionId);
        _answers = next;
      } else {
        _answers = {..._answers, questionId: previous};
      }
    });
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.questionAnswersSaveError)),
    );
  }

  Future<void> _setVisibility(
    ProfileQuestionAnswerRepository repository,
    String questionId,
    bool isVisible,
  ) async {
    final result = await repository.setVisibility(
      questionId: questionId,
      isVisible: isVisible,
    );
    if (!mounted || !result.isSuccess) {
      return;
    }
    setState(() {
      final current = _profileAnswers[questionId];
      if (current != null) {
        _profileAnswers = {
          ..._profileAnswers,
          questionId: ProfileQuestionAnswer(
            questionId: current.questionId,
            answerId: current.answerId,
            isVisible: isVisible,
            createdAt: current.createdAt,
            updatedAt: DateTime.now(),
          ),
        };
      }
    });
  }
}

class _AnswerEditor extends StatelessWidget {
  const _AnswerEditor({
    required this.questionId,
    required this.answerId,
    required this.locale,
    required this.isVisible,
    this.onSave,
    this.onVisibilityChanged,
  });

  final String questionId;
  final String answerId;
  final String locale;
  final bool isVisible;
  final ValueChanged<String>? onSave;
  final ValueChanged<bool>? onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                if (option.labelFor(locale).trim().isNotEmpty)
                  MevoraChip(
                    label: option.labelFor(locale),
                    selected: option.id == answerId,
                    wrapLabel: true,
                    onSelected: onSave == null
                        ? null
                        : (_) => onSave!(option.id),
                  ),
            ],
          ),
          if (onVisibilityChanged != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.showOnProfile),
              value: isVisible,
              onChanged: onVisibilityChanged,
            ),
          ],
        ],
      ),
    );
  }
}
