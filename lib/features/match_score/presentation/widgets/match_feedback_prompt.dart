import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/match_score_scope.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';
import 'package:mevora/features/match_score/domain/repositories/match_score_repository.dart';
import 'package:mevora/features/match_score/domain/services/match_feedback_filter.dart';
import 'package:mevora/features/match_score/domain/services/match_score_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class MatchFeedbackPrompt extends StatefulWidget {
  const MatchFeedbackPrompt({
    super.key,
    required this.pending,
    required this.repository,
  });

  final PendingMatchFeedback pending;
  final MatchScoreRepository repository;

  @override
  State<MatchFeedbackPrompt> createState() => _MatchFeedbackPromptState();
}

class _MatchFeedbackPromptState extends State<MatchFeedbackPrompt> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final cleaned = MatchFeedbackFilter.sanitize(_controller.text);
    if (!MatchFeedbackFilter.isAcceptable(cleaned)) {
      setState(() => _error = l10n.matchFeedbackTooShort);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await widget.repository.submitFeedback(
      matchId: widget.pending.matchId,
      text: cleaned,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (result.isError) {
      setState(() => _error = l10n.matchFeedbackFailed);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.matchFeedbackThanks)),
    );
  }

  Future<void> _skip() {
    return widget.repository.dismissFeedback(matchId: widget.pending.matchId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.matchFeedbackTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.matchFeedbackMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              MevoraTextField(
                controller: _controller,
                hint: l10n.matchFeedbackHint,
                maxLines: 3,
                minLines: 2,
                maxLength: MatchScorePolicy.feedbackMaxChars,
                enabled: !_submitting,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: MevoraButton(
                      label: l10n.skip,
                      variant: MevoraButtonVariant.ghost,
                      onPressed: _submitting ? null : () => unawaited(_skip()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MevoraButton(
                      label: l10n.matchFeedbackSubmit,
                      isLoading: _submitting,
                      onPressed: _submitting ? null : () => unawaited(_submit()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MatchFeedbackForChat extends StatelessWidget {
  const MatchFeedbackForChat({super.key, required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = MatchScoreScope.maybeOf(context);
    if (uid == null || repository == null) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<PendingMatchFeedback>>(
      stream: repository.watchPendingFeedback(uid),
      builder: (context, snapshot) {
        final pending = snapshot.data
            ?.where((item) => item.matchId == matchId)
            .firstOrNull;
        if (pending == null) {
          return const SizedBox.shrink();
        }
        return MatchFeedbackPrompt(
          pending: pending,
          repository: repository,
        );
      },
    );
  }
}

/// Shows a private feedback sheet to the remaining user after unmatch/block.
class MatchFeedbackHost extends StatefulWidget {
  const MatchFeedbackHost({super.key, required this.child});

  final Widget child;

  @override
  State<MatchFeedbackHost> createState() => _MatchFeedbackHostState();
}

class _MatchFeedbackHostState extends State<MatchFeedbackHost> {
  StreamSubscription<List<PendingMatchFeedback>>? _sub;
  String? _uid;
  final Set<String> _shown = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = MatchScoreScope.maybeOf(context);
    if (uid == _uid && _sub != null) {
      return;
    }
    _uid = uid;
    unawaited(_sub?.cancel());
    _sub = null;
    if (uid == null || repository == null) {
      return;
    }
    _sub = repository.watchPendingFeedback(uid).listen(
      (items) {
        if (!mounted || items.isEmpty) {
          return;
        }
        final next = items
            .where((item) => !_shown.contains(item.matchId))
            .firstOrNull;
        if (next == null) {
          return;
        }
        _shown.add(next.matchId);
        unawaited(_show(next, repository));
      },
      onError: (_) {
        // Permission-denied / App Check noise must not take down the shell.
      },
    );
  }

  Future<void> _show(
    PendingMatchFeedback pending,
    MatchScoreRepository repository,
  ) async {
    if (!mounted) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    await MevoraBottomSheet.show<void>(
      context,
      title: l10n.matchFeedbackTitle,
      child: MatchFeedbackPrompt(pending: pending, repository: repository),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
