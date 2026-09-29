import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/localization/l10n_errors.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_lab_discover_entry.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/relationship_learning_page.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_meter.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';
import 'package:mevora/shared/widgets/mevora_selectable_tile.dart';

/// "Mevora Beni Tanısın": the permanent place where a member sees what Mevora
/// knows about what matters to them, opens today's questions, and changes
/// earlier answers. Every number comes from the server's real coverage and
/// counts; every sentence is one of the member's own answers read back.
class LearningDashboardPage extends StatefulWidget {
  const LearningDashboardPage({super.key, this.repository});

  /// Injected by tests; otherwise read from [RelationshipLearningScope].
  final RelationshipLearningRepository? repository;

  @override
  State<LearningDashboardPage> createState() => _LearningDashboardPageState();
}

class _LearningDashboardPageState extends State<LearningDashboardPage> {
  RelationshipLearningRepository? _repository;
  AnalyticsProvider? _analytics;
  RelationshipLearningState? _state;
  String? _error;
  bool _loading = true;
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repository != null) {
      return;
    }
    final scope = RelationshipLearningScope.maybeOf(context);
    _repository = widget.repository ?? scope?.repository;
    _analytics = scope?.analyticsProvider;
    unawaited(_load());
  }

  void _log(String name, [Map<String, Object> params = const {}]) {
    unawaited(
      _analytics?.logEvent(name, parameters: params).catchError((Object _) {}),
    );
  }

  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = _state == null;
      _error = null;
    });
    final result = await repository.loadState();
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      result.when(
        success: (state) => _state = state,
        err: (failure) => _error = failure.message,
      );
    });
    if (!_opened && result.isSuccess) {
      _opened = true;
      _log(AnalyticsEvents.relationshipLearningDashboardOpened, {
        'progress_bucket':
            ((_state!.overview.overallProgress * 10).floor() * 10),
      });
    }
  }

  Future<void> _openToday() async {
    _log(AnalyticsEvents.relationshipLearningContinueStarted, {
      'answered': _state?.summary.today.answered ?? 0,
    });
    final location = RelationshipLearningPage.location(source: 'dashboard');
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      await router.push<Object?>(location);
    } else {
      await Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          builder: (_) => RelationshipLearningPage(
            source: 'dashboard',
            repository: _repository,
          ),
        ),
      );
    }
    if (mounted) {
      await _load();
    }
  }

  Future<void> _edit(AnsweredLearningQuestion answered) async {
    final repository = _repository;
    if (repository == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final question = answered.question;
    final chosen = await MevoraBottomSheet.show<String>(
      context,
      title: question.promptFor(language),
      child: _AnswerPicker(question: question, language: language),
    );
    if (chosen == null || chosen == question.answerId || !mounted) {
      return;
    }
    final result = await repository.updateAnswer(
      questionId: question.id,
      questionVersion: question.version,
      answerId: chosen,
    );
    if (!mounted) {
      return;
    }
    if (result.isSuccess) {
      _log(AnalyticsEvents.relationshipLearningAnswerEdited, {
        'category': question.category,
      });
      await _load();
    } else {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(l10n.learningSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.learningProfileTitle)),
      body: SafeArea(child: _body(context, l10n)),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n) {
    final state = _state;
    if (_loading && state == null) {
      return const MevoraLoading.page();
    }
    if (state == null) {
      return MevoraErrorView(
        title: l10n.learningLoadErrorTitle,
        message: L10nErrors.message(l10n, _error),
        onRetry: () => unawaited(_load()),
      );
    }
    final overview = state.overview;
    final language = Localizations.localeOf(context).languageCode;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        key: const Key('learningDashboardList'),
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          _Header(overview: overview),
          const SizedBox(height: AppSpacing.md),
          _TodayCard(summary: state.summary, onOpen: _openToday),
          const SizedBox(height: AppSpacing.xl),
          MevoraSectionHeader(title: l10n.learningDashboardCategoriesTitle),
          const SizedBox(height: AppSpacing.s12),
          for (final category in overview.categories)
            _CategoryRow(category: category),
          if (overview.highlights.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            MevoraSectionHeader(
              title: l10n.learningDashboardHighlightsTitle,
              subtitle: l10n.learningDashboardHighlightsSubtitle,
            ),
            const SizedBox(height: AppSpacing.s12),
            MevoraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final highlight in overview.highlights)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Text(
                        highlight.textFor(language),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (HumorScope.maybeOf(context) != null) ...[
            const SizedBox(height: AppSpacing.xl),
            const HumorLabDiscoverEntry(),
          ],
          if (overview.answered.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            MevoraListGroup(
              title: l10n.learningDashboardAnswersTitle,
              footer: l10n.learningDashboardAnswersFooter,
              children: [
                for (final answered in overview.answered)
                  MevoraListRow(
                    key: Key('learningAnswer_${answered.question.id}'),
                    title: answered.question.promptFor(language),
                    subtitle: _chosenLabel(answered.question, language),
                    onTap: () => unawaited(_edit(answered)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String? _chosenLabel(LearningQuestion question, String language) {
    for (final option in question.options) {
      if (option.id == question.answerId) {
        return option.labelFor(language);
      }
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.overview});

  final LearningOverview overview;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent = (overview.overallProgress * 100).round();
    return MevoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.learningDashboardHeadline,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.learningDashboardPercent(percent),
            key: const Key('learningOverallPercent'),
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: AppSpacing.s12),
          MevoraMeter(
            value: overview.overallProgress,
            height: 8,
            semanticLabel: l10n.learningDashboardHeadline,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.learningDashboardThisMonth(overview.totals.thisMonth),
            key: const Key('learningThisMonth'),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.learningDashboardTotals(
              overview.totals.total,
              overview.totals.completedDays,
            ),
            key: const Key('learningTotals'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.learningDashboardBody,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.summary, required this.onOpen});

  final LearningSummary summary;
  final Future<void> Function() onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final today = summary.today;
    if (today.completed) {
      return Text(
        l10n.learningDashboardTodayDone,
        key: const Key('learningDashboardTodayDone'),
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    return MevoraButton(
      key: const Key('learningDashboardToday'),
      label: l10n.learningDashboardToday(today.answered, today.total),
      onPressed: () => unawaited(onOpen()),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category});

  final LearningCategoryProgress category;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final label = learningCategoryLabel(l10n, category.key);
    final percent = (category.progress * 100).round();
    return Padding(
      key: Key('learningCategory_${category.key}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
              Text(
                l10n.learningDashboardPercent(percent),
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          MevoraMeter(value: category.progress, semanticLabel: label),
        ],
      ),
    );
  }
}

/// Localized name of a dashboard category key from the server.
String learningCategoryLabel(AppLocalizations l10n, String key) {
  return switch (key) {
    'relationship' => l10n.learningCategoryRelationship,
    'communication' => l10n.learningCategoryCommunication,
    'lifestyle' => l10n.learningCategoryLifestyle,
    'values' => l10n.learningCategoryValues,
    'humor' => l10n.learningCategoryHumor,
    'music' => l10n.learningCategoryMusic,
    'interests' => l10n.learningCategoryInterests,
    _ => key,
  };
}

class _AnswerPicker extends StatelessWidget {
  const _AnswerPicker({required this.question, required this.language});

  final LearningQuestion question;
  final String language;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in question.options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s12),
            child: MevoraSelectableTile(
              key: Key('learningEditOption_${option.id}'),
              title: option.labelFor(language),
              selected: option.id == question.answerId,
              onTap: () => Navigator.of(context).pop(option.id),
            ),
          ),
      ],
    );
  }
}
