import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/profile/domain/models/profile_question_answer.dart';
import 'package:mevora/features/profile/domain/repositories/profile_question_answer_repository.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_access.dart';
import 'package:mevora/features/profile/domain/services/profile_question_answer_display.dart';
import 'package:mevora/features/profile/presentation/pages/profile_question_answers_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';

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
  var _premiumRequired = false;
  String? _error;

  String? _boundViewerUid;
  String? _boundUid;
  bool _boundIsOwner = false;
  var _partnerFetchToken = 0;

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
      _partnerFetchToken += 1;
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
        _premiumRequired = false;
      });
      return;
    }

    if (widget.isOwner) {
      _canView = true;
      _matchChecked = true;
      _premiumRequired = false;
      _subscribeAnswers(repository);
      return;
    }

    if (!widget.requireMatch) {
      _canView = true;
      _matchChecked = true;
      unawaited(_loadPartnerAnswers(repository));
      return;
    }

    final social = SocialScope.maybeOf(context);
    if (social == null) {
      setState(() {
        _loading = false;
        _canView = false;
        _matchChecked = true;
        _premiumRequired = false;
      });
      return;
    }

    _matchSubscription = ProfileQuestionAnswerAccess.watchCanView(
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
          unawaited(_loadPartnerAnswers(repository));
        } else {
          unawaited(_answersSubscription?.cancel());
          _answersSubscription = null;
          setState(() {
            _answers = const [];
            _loading = false;
            _error = null;
            _premiumRequired = false;
          });
        }
      },
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _canView = false;
          _matchChecked = true;
          _loading = false;
          _answers = const [];
          _error = null;
          _premiumRequired = false;
        });
      },
    );
  }

  Future<void> _loadPartnerAnswers(
    ProfileQuestionAnswerRepository repository,
  ) async {
    final token = ++_partnerFetchToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await repository.fetchPartnerAnswers(widget.uid);
    if (!mounted || token != _partnerFetchToken) {
      return;
    }
    switch (result) {
      case Success(:final value):
        if (value.matchRequired) {
          setState(() {
            _canView = false;
            _premiumRequired = false;
            _answers = const [];
            _loading = false;
            _error = null;
          });
          return;
        }
        setState(() {
          _answers = value.items;
          _premiumRequired = value.premiumRequired || value.locked;
          _loading = false;
          _error = null;
        });
      case Err():
        setState(() {
          _loading = false;
          _error = AppLocalizations.of(context).questionAnswersLoadError;
        });
    }
  }

  void _subscribeAnswers(ProfileQuestionAnswerRepository repository) {
    // Hard gate: peer profiles must never Firestore-watch questionAnswers.
    if (!widget.isOwner) {
      unawaited(_loadPartnerAnswers(repository));
      return;
    }
    unawaited(_answersSubscription?.cancel());
    _loading = true;
    _answersSubscription = repository
        .watchAnswers(widget.uid, visibleOnly: false)
        .listen(
      (value) async {
        if (!mounted) {
          return;
        }
        if (widget.isOwner && value.isEmpty && !_syncAttempted) {
          _syncAttempted = true;
          try {
            await repository
                .syncFromMatching()
                .timeout(const Duration(seconds: 12));
          } on Object {
            // Stream stays subscribed; UI shows empty / error below.
          }
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
    _partnerFetchToken += 1;
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
    final showPremiumGate = !widget.isOwner && _premiumRequired;

    final content = Padding(
      padding: widget.highlightWhenMatched
          ? const EdgeInsets.all(AppSpacing.md)
          : EdgeInsets.zero,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.highlightWhenMatched
                        ? l10n.chatDiscoverAnswersPrompt
                        : l10n.questionAnswersTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (widget.showEditAction)
                  TextButton(
                    onPressed: () => context.push(AppRoutes.profileAnswers),
                    child: Text(l10n.profileAnswersEdit),
                  ),
              ],
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
            if (showPremiumGate) ...[
              const SizedBox(height: AppSpacing.sm),
              _PremiumAnswersBanner(
                onUpgrade: () => context.push(AppRoutes.boost),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            for (final card in preview) ...[
              _AnswerCard(
                display: card,
                onUpgrade: showPremiumGate
                    ? () => context.push(AppRoutes.boost)
                    : null,
              ),
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
                    premiumLocked: showPremiumGate,
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
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionAnswersTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.questionAnswersEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.questionAnswersEmptyHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onEdit != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onEdit,
                  child: Text(l10n.profileAnswersEdit),
                ),
              ),
            ],
          ],
        ),
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.questionAnswersTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumAnswersBanner extends StatelessWidget {
  const _PremiumAnswersBanner({required this.onUpgrade});

  final VoidCallback onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: AppColors.premiumGradient,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionAnswersPremiumLockedMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonal(
                onPressed: onUpgrade,
                child: Text(l10n.questionAnswersPremiumUnlockCta),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.display, this.onUpgrade});

  final ProfileQuestionAnswerDisplay display;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    display.questionText,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (display.isLocked)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.questionAnswersPremiumAnswerHidden,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (onUpgrade != null)
                          TextButton(
                            onPressed: onUpgrade,
                            child: Text(l10n.questionAnswersPremiumUnlockCta),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            else
              Text(
                '"${display.answerText}"',
                style: theme.textTheme.bodyLarge,
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens matched user's question answers from chat.
Future<void> showMatchedProfileAnswersSheet(
  BuildContext context, {
  required String otherUid,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: ProfileQuestionAnswersSection(
            uid: otherUid,
            requireMatch: true,
            highlightWhenMatched: true,
            previewLimit: 20,
          ),
        ),
      );
    },
  );
}

class _PeerEmptyAnswers extends StatelessWidget {
  const _PeerEmptyAnswers({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.questionAnswersTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
