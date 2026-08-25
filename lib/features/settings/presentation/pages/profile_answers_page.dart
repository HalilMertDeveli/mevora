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
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

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
  var _loadStarted = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited scopes are not safe to read from [initState]. Start once here.
    if (_loadStarted) {
      return;
    }
    _loadStarted = true;
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_profileSubscription?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = RelationshipScope.maybeOf(context);
    final profileAnswers = RelationshipScope.profileAnswersOf(context);
    if (uid == null || repository == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
          _answers = const {};
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    unawaited(_profileSubscription?.cancel());
    if (profileAnswers != null) {
      _profileSubscription = profileAnswers.watchAnswers(uid).listen(
        (items) {
          if (!mounted) {
            return;
          }
          setState(() {
            _profileAnswers = {
              for (final item in items) item.questionId: item,
            };
            // Prefer live profile answers when the one-shot load was empty.
            if (_answers.isEmpty && items.isNotEmpty) {
              _answers = {
                for (final item in items)
                  if (item.answerId.trim().isNotEmpty)
                    item.questionId: item.answerId,
              };
              _loading = false;
              _error = null;
            }
          });
        },
        onError: (_) {
          if (!mounted || !_loading) {
            return;
          }
          setState(() {
            _loading = false;
            _error = AppLocalizations.of(context).questionAnswersLoadError;
          });
        },
      );
      try {
        await profileAnswers
            .syncFromMatching()
            .timeout(const Duration(seconds: 12));
      } on Object {
        // Continue with whatever Firestore already has.
      }
    }

    try {
      final result = await repository
          .getSavedAnswers(uid)
          .timeout(const Duration(seconds: 12));
      if (!mounted) {
        return;
      }
      if (result.isError) {
        setState(() {
          _loading = false;
          if (_answers.isEmpty && _profileAnswers.isEmpty) {
            _error = AppLocalizations.of(context).questionAnswersLoadError;
          }
        });
        return;
      }
      final loaded = result.valueOrNull ?? const <String, String>{};
      setState(() {
        if (loaded.isNotEmpty) {
          _answers = loaded;
        } else if (_profileAnswers.isNotEmpty) {
          _answers = {
            for (final item in _profileAnswers.values)
              if (item.answerId.trim().isNotEmpty)
                item.questionId: item.answerId,
          };
        } else {
          _answers = const {};
        }
        _loading = false;
        _error = null;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        if (_answers.isEmpty) {
          _error = AppLocalizations.of(context).questionAnswersLoadError;
        }
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
          ? MevoraLoading.page(
              message: l10n.loading,
              asset: MevoraRiveAssets.loading,
            )
          : _error != null && _answers.isEmpty
          ? MevoraErrorView(
              message: _error,
              onRetry: () {
                unawaited(_load());
              },
            )
          : SafeArea(
              child: _answers.isEmpty
                  ? MevoraEmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      riveAsset: MevoraRiveAssets.empty,
                      title: l10n.questionAnswersEmpty,
                      message: l10n.questionAnswersEmptyHint,
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
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final settings = SettingsScope.maybeOf(context);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final previous = _answers[questionId];
    if (previous == answerId) {
      return;
    }
    setState(() {
      _answers = {..._answers, questionId: answerId};
      final current = _profileAnswers[questionId];
      if (current != null) {
        _profileAnswers = {
          ..._profileAnswers,
          questionId: ProfileQuestionAnswer(
            questionId: current.questionId,
            answerId: answerId,
            isVisible: current.isVisible,
            createdAt: current.createdAt,
            updatedAt: DateTime.now(),
          ),
        };
      }
    });
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
