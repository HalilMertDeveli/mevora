import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_access.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';
import 'package:mevora/features/profile/presentation/pages/profile_question_answers_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';
import 'package:mevora/shared/widgets/mevora_section_header.dart';

class ProfileQuestionAnswersSection extends StatefulWidget {
  const ProfileQuestionAnswersSection({
    super.key,
    required this.uid,
    this.isOwner = false,
    this.previewLimit = 3,
    this.showEditAction = false,
    this.requireMatch = true,
    this.highlightWhenMatched = false,
    this.viewerUid,
  });

  final String uid;
  final bool isOwner;
  final int previewLimit;
  final bool showEditAction;
  final bool requireMatch;
  final bool highlightWhenMatched;
  final String? viewerUid;

  @override
  State<ProfileQuestionAnswersSection> createState() =>
      _ProfileQuestionAnswersSectionState();
}

class _ProfileQuestionAnswersSectionState
    extends State<ProfileQuestionAnswersSection> {
  StreamSubscription<List<ProfileQuestionAnswer>>? _answersSubscription;
  StreamSubscription<bool>? _matchSubscription;
  List<ProfileQuestionAnswer> _answers = const [];
  var _loading = true;
  var _syncAttempted = false;
  var _canView = false;
  var _matchChecked = false;
  String? _error;

  String? _boundViewerUid;
  String? _boundUid;
  bool _boundIsOwner = false;

  ProfileQuestionAnswerRepository? get _repository =>
      RelationshipScope.profileAnswersOf(context);

  String? get _viewerUid =>
      widget.viewerUid ?? AuthScope.maybeOf(context)?.user?.id;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureListening();
  }

  @override
  void didUpdateWidget(covariant ProfileQuestionAnswersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.isOwner != widget.isOwner ||
        oldWidget.viewerUid != widget.viewerUid) {
      unawaited(_answersSubscription?.cancel());
      unawaited(_matchSubscription?.cancel());
      _answersSubscription = null;
      _matchSubscription = null;
      _syncAttempted = false;
      _boundUid = null;
      _ensureListening();
    }
  }

  void _ensureListening() {
    final viewerUid = _viewerUid;
    if (_boundUid == widget.uid &&
        _boundIsOwner == widget.isOwner &&
        _boundViewerUid == viewerUid &&
        (_answersSubscription != null ||
            _matchSubscription != null ||
            _matchChecked)) {
      return;
    }
    _boundUid = widget.uid;
    _boundIsOwner = widget.isOwner;
    _boundViewerUid = viewerUid;
    _listen();
  }

  void _listen() {
    final repository = _repository;
    final viewerUid = _viewerUid;
    if (repository == null || viewerUid == null) {
      setState(() {
        _loading = false;
        _answers = const [];
        _canView = false;
        _matchChecked = true;
      });
      return;
    }

    if (widget.isOwner) {
      _canView = true;
      _matchChecked = true;
      _subscribeAnswers(repository);
      return;
    }

    if (!widget.requireMatch) {
      _canView = true;
      _matchChecked = true;
      _subscribeAnswers(repository);
      return;
    }

    final social = SocialScope.maybeOf(context);
    if (social == null) {
      setState(() {
        _loading = false;
        _canView = false;
        _matchChecked = true;
      });
      return;
    }

    _matchSubscription =
        ProfileQuestionAnswerAccess.watchCanView(
          matches: social.matchRepository,
          viewerUid: viewerUid,
          profileUid: widget.uid,
        ).listen(
          (canView) {
            if (!mounted) {
              return;
            }
            setState(() {
              _canView = canView;
              _matchChecked = true;
            });
            if (canView) {
              _subscribeAnswers(repository);
            } else {
              unawaited(_answersSubscription?.cancel());
              _answersSubscription = null;
              setState(() {
                _answers = const [];
                _loading = false;
                _error = null;
              });
            }
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _canView = false;
              _matchChecked = true;
              _loading = false;
              _answers = const [];
              _error = null;
            });
          },
        );
  }

  void _subscribeAnswers(ProfileQuestionAnswerRepository repository) {
    unawaited(_answersSubscription?.cancel());
    final visibleOnly = !widget.isOwner;
    _loading = true;
    _answersSubscription = repository
        .watchAnswers(widget.uid, visibleOnly: visibleOnly)
        .listen(
          (value) async {
            if (!mounted) {
              return;
            }
            if (widget.isOwner && value.isEmpty && !_syncAttempted) {
              _syncAttempted = true;
              try {
                await repository.syncFromMatching().timeout(
                  const Duration(seconds: 12),
                );
              } on Object {
                // Stream stays subscribed; UI shows empty / error below.
              }
              // Do not paint the pre-sync empty snapshot as final — wait for the
              // next Firestore emission after dual-write / backfill.
              if (!mounted) {
                return;
              }
              setState(() {
                _loading = false;
                _error = null;
                _answers = value;
              });
              return;
            }
            if (!mounted) {
              return;
            }
            setState(() {
              _answers = value;
              _loading = false;
              _error = null;
            });
          },
          onError: (_) {
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _error = AppLocalizations.of(context).questionAnswersLoadError;
            });
          },
        );
  }

  @override
  void dispose() {
    unawaited(_answersSubscription?.cancel());
    unawaited(_matchSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    if (_repository == null) {
      return const SizedBox.shrink();
    }

    if (!_matchChecked) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!widget.isOwner && widget.requireMatch && !_canView) {
      return _LockedAnswersCard(message: l10n.questionAnswersMatchRequired);
    }

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(_error!, style: Theme.of(context).textTheme.bodyMedium);
    }

    final visibleAnswers = widget.isOwner
        ? _answers
        : _answers.where((item) => item.isVisible).toList(growable: false);
    if (visibleAnswers.isEmpty) {
      if (!widget.isOwner) {
        if (widget.highlightWhenMatched) {
          return _PeerEmptyAnswers(message: l10n.questionAnswersPeerEmpty);
        }
        return const SizedBox.shrink();
      }
      return _OwnerEmptyAnswers(
        onEdit: widget.showEditAction
            ? () => context.push(AppRoutes.profileAnswers)
            : null,
      );
    }

    final cards = visibleAnswers
        .map((item) => ProfileQuestionAnswerDisplay.resolve(item, locale))
        .whereType<ProfileQuestionAnswerDisplay>()
        .toList(growable: false);
    if (cards.isEmpty) {
      return const SizedBox.shrink();
    }

    final preview = cards.take(widget.previewLimit).toList(growable: false);
    final hiddenCount = cards.length - preview.length;
    final theme = Theme.of(context);

    final content = Padding(
      padding: widget.highlightWhenMatched
          ? const EdgeInsets.all(AppSpacing.md)
          : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MevoraSectionHeader(
            title: widget.highlightWhenMatched
                ? l10n.chatDiscoverAnswersPrompt
                : l10n.questionAnswersTitle,
            icon: MevoraIcons.questions,
            iconColor: context.palette.compatibility,
            actionLabel: widget.showEditAction ? l10n.profileAnswersEdit : null,
            onAction: widget.showEditAction
                ? () => context.push(AppRoutes.profileAnswers)
                : null,
          ),
          if (widget.highlightWhenMatched) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.questionAnswersMatchedSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s12),
          for (final card in preview) ...[
            _AnswerCard(display: card),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (hiddenCount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => showProfileQuestionAnswersSheet(
                  context,
                  uid: widget.uid,
                  isOwner: widget.isOwner,
                  answers: visibleAnswers,
                ),
                child: Text(l10n.seeAllAnswers(hiddenCount)),
              ),
            ),
        ],
      ),
    );

    if (!widget.highlightWhenMatched) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.palette.compatibilityContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: content,
    );
  }
}

class _OwnerEmptyAnswers extends StatelessWidget {
  const _OwnerEmptyAnswers({this.onEdit});

  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return MevoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const MevoraIconBadge(
                icon: MevoraIcons.questions,
                tone: MevoraTone.compatibility,
                size: 40,
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Text(
                  l10n.questionAnswersTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          Text(l10n.questionAnswersEmpty, style: theme.textTheme.bodyLarge),
          const SizedBox(height: AppSpacing.xs),
          Text(l10n.questionAnswersEmptyHint, style: theme.textTheme.bodySmall),
          if (onEdit != null) ...[
            const SizedBox(height: AppSpacing.md),
            MevoraButton(
              label: l10n.profileAnswersEdit,
              variant: MevoraButtonVariant.tonal,
              size: MevoraButtonSize.small,
              isExpanded: false,
              onPressed: onEdit,
            ),
          ],
        ],
      ),
    );
  }
}

class _LockedAnswersCard extends StatelessWidget {
  const _LockedAnswersCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return MevoraCard(
      emphasis: MevoraCardEmphasis.quiet,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            MevoraIcons.locked,
            size: 18,
            color: context.palette.textSecondary,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.questionAnswersTitle,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(message, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One answered question, set like a pull quote: the question small, the
/// answer in the serif — the person's own words are the point.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.display});

  final ProfileQuestionAnswerDisplay display;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    return MevoraCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            display.questionText,
            style: theme.textTheme.labelMedium?.copyWith(
              color: p.compatibility,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(display.answerText, style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }
}

/// Opens matched user's question answers from chat.
Future<void> showMatchedProfileAnswersSheet(
  BuildContext context, {
  required String otherUid,
}) {
  return MevoraBottomSheet.show<void>(
    context,
    scrollable: true,
    child: ProfileQuestionAnswersSection(
      uid: otherUid,
      requireMatch: true,
      highlightWhenMatched: true,
      previewLimit: 20,
    ),
  );
}

class _PeerEmptyAnswers extends StatelessWidget {
  const _PeerEmptyAnswers({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return MevoraCard(
      emphasis: MevoraCardEmphasis.quiet,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.questionAnswersTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
