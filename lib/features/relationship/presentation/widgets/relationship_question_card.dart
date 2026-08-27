import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_profile_details_page.dart';
import 'package:mevora/features/relationship/data/catalog/relationship_questions.dart';
import 'package:mevora/features/relationship/domain/entities/relationship_match_suggestion.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';
import 'package:mevora/features/relationship/presentation/widgets/mevora_hour_event_card.dart';
import 'package:mevora/features/relationship/domain/entities/mevora_hour_phase.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

class RelationshipDiscoverySync extends StatefulWidget {
  const RelationshipDiscoverySync({
    super.key,
    required this.controller,
    required this.child,
    this.discoveryVisible = false,
    this.normalMatchCount = 0,
  });

  final RelationshipController controller;
  final Widget child;
  final bool discoveryVisible;
  final int normalMatchCount;

  @override
  State<RelationshipDiscoverySync> createState() =>
      _RelationshipDiscoverySyncState();
}

class _RelationshipDiscoverySyncState extends State<RelationshipDiscoverySync> {
  var _started = false;
  bool? _lastVisible;
  int? _lastMatchCount;

  @override
  void initState() {
    super.initState();
    _ensureStarted();
    _pushVisibility();
  }

  @override
  void didUpdateWidget(RelationshipDiscoverySync oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _started = false;
      _lastVisible = null;
      _lastMatchCount = null;
      _ensureStarted();
    }
    _pushVisibility();
  }

  void _ensureStarted() {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(widget.controller.start());
  }

  void _pushVisibility() {
    if (_lastMatchCount != widget.normalMatchCount) {
      _lastMatchCount = widget.normalMatchCount;
      widget.controller.setNormalMatchCount(widget.normalMatchCount);
    }
    if (_lastVisible != widget.discoveryVisible) {
      _lastVisible = widget.discoveryVisible;
      widget.controller.setDiscoveryVisible(widget.discoveryVisible);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RelationshipPromptHost extends StatefulWidget {
  const RelationshipPromptHost({
    super.key,
    required this.controller,
    required this.child,
    this.discoveryVisible = false,
    this.normalMatchCount = 0,
  });

  final RelationshipController controller;
  final Widget child;
  final bool discoveryVisible;
  final int normalMatchCount;

  @override
  State<RelationshipPromptHost> createState() => _RelationshipPromptHostState();
}

class _RelationshipPromptHostState extends State<RelationshipPromptHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncHost);
    _syncWhenVisible();
  }

  @override
  void didUpdateWidget(RelationshipPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncHost);
      widget.controller.addListener(_syncHost);
    }
    if (oldWidget.discoveryVisible != widget.discoveryVisible ||
        oldWidget.normalMatchCount != widget.normalMatchCount ||
        oldWidget.controller != widget.controller) {
      _syncWhenVisible();
    }
  }

  /// Only applies "visible" — never forces hidden. AppShell
  /// [RelationshipDiscoverySync] owns tab-off visibility so an offstage
  /// Discover page cannot re-arm timers after the user left the tab.
  void _syncWhenVisible() {
    if (!widget.discoveryVisible) {
      return;
    }
    widget.controller.setNormalMatchCount(widget.normalMatchCount);
    widget.controller.setDiscoveryVisible(true);
    unawaited(widget.controller.start());
  }

  void _syncHost() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHost);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final question = controller.currentQuestion;
    // Offstage discovery tabs keep this host mounted; only paint when visible.
    final showPrompt = widget.discoveryVisible;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (showPrompt && controller.hasUnavailableFallback)
          Positioned.fill(
            child: RelationshipQuestionUnavailableCard(
              onDismiss: controller.dismissUnavailable,
            ),
          )
        else if (showPrompt && controller.isResultVisible)
          Positioned.fill(
            child: RelationshipTestResultCard(
              results: controller.testResults,
              empty: controller.hasEmptyResults,
              onDismiss: () {
                unawaited(controller.dismissResults());
              },
              onAcceptMatch: () {
                unawaited(controller.acceptMatchResult());
              },
            ),
          )
        else if (showPrompt && controller.waitingForRoundResult)
          Positioned.fill(
            child: MevoraHourEventCard(
              phase: MevoraHourPhase.answered,
              hourLabel: controller.hourlyRoundHour,
              nextHourLabel: controller.nextMevoraHourLabel,
              countdown: controller.hourlyCountdownRemaining,
              reminderEnabled: controller.mevoraHourReminderEnabled,
              onPrimary: controller.acknowledgeWaitingOverlay,
              onRemind: () {},
            ),
          )
        else if (showPrompt && question != null)
          Positioned.fill(
            child: RelationshipQuestionCard(
              question: question,
              answeredCount: controller.sessionIndex + 1,
              totalCount: controller.sessionLength,
              submitting: controller.submitting,
              lastError: controller.lastError,
              onAnswer: (answerId) {
                unawaited(controller.answer(answerId));
              },
            ),
          )
        else if (showPrompt && controller.isContinuePromptVisible)
          Positioned.fill(
            child: RelationshipContinueMatchingCard(
              onContinue: () {
                unawaited(controller.continueMatchingEvents());
              },
              onNotNow: () {
                unawaited(controller.pauseMatchingEvents());
              },
            ),
          )
        else if (showPrompt &&
            controller.isOfferVisible &&
            controller.isHourlyOffer)
          Positioned.fill(
            child: MevoraHourEventCard(
              phase: MevoraHourPhase.live,
              hourLabel: controller.hourlyRoundHour,
              nextHourLabel: controller.nextMevoraHourLabel,
              countdown: controller.hourlyCountdownRemaining,
              reminderEnabled: controller.mevoraHourReminderEnabled,
              onPrimary: () {
                unawaited(controller.acceptOffer());
              },
              onRemind: () {
                unawaited(_enableMevoraHourReminder(context, controller));
              },
              onDismiss: () {
                unawaited(controller.dismissOffer());
              },
            ),
          )
        else if (showPrompt && controller.isOfferVisible)
          Positioned.fill(
            child: RelationshipTestOfferCard(
              onStart: () {
                unawaited(controller.acceptOffer());
              },
              onLater: () {
                unawaited(controller.dismissOffer());
              },
              isInitial: controller.isInitialOffer,
            ),
          )
        else if (showPrompt &&
            (controller.mevoraHourPhase == MevoraHourPhase.upcoming ||
                controller.mevoraHourPhase == MevoraHourPhase.ended))
          Positioned(
            left: AppSpacing.md,
            right: AppSpacing.md,
            bottom: AppSpacing.lg,
            child: MevoraHourEventCard(
              phase: controller.mevoraHourPhase,
              compact: true,
              hourLabel: controller.mevoraHourPhase == MevoraHourPhase.ended
                  ? controller.hourlyRoundHour
                  : controller.nextMevoraHourLabel ??
                      controller.hourlyRoundHour,
              nextHourLabel: controller.nextMevoraHourLabel,
              countdown: controller.hourlyCountdownRemaining,
              reminderEnabled: controller.mevoraHourReminderEnabled,
              onPrimary: controller.openLiveMevoraHour,
              onRemind: () {
                unawaited(_enableMevoraHourReminder(context, controller));
              },
            ),
          ),
      ],
    );
  }
}

Future<void> _enableMevoraHourReminder(
  BuildContext context,
  RelationshipController controller,
) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final social = SocialScope.maybeOf(context);
  final uid = social?.uidSource.currentUid;
  if (social == null || uid == null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mevoraHourReminderNeedSignIn)),
    );
    return;
  }
  final perm = await FirebaseMessagingDataSource().requestPermission();
  if (!context.mounted) {
    return;
  }
  if (perm.failureOrNull != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.mevoraHourReminderNeedPermission)),
    );
    return;
  }
  final prefs = await social.notificationRepository.loadPrefs(uid);
  await social.notificationRepository.savePrefs(
    uid,
    prefs.copyWith(mevoraHourReminders: true),
  );
  controller.setMevoraHourReminderEnabled(true);
  messenger.showSnackBar(
    SnackBar(content: Text(l10n.mevoraHourReminderSaved)),
  );
}

class RelationshipQuestionCard extends StatelessWidget {
  const RelationshipQuestionCard({
    super.key,
    required this.question,
    required this.answeredCount,
    required this.totalCount,
    required this.onAnswer,
    this.submitting = false,
    this.lastError,
  });

  final RelationshipQuestion question;
  final int answeredCount;
  final int totalCount;
  final ValueChanged<String> onAnswer;
  final bool submitting;
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: AnimatedOpacity(
            duration: AppDurations.short,
            opacity: submitting ? 0.72 : 1,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: MevoraCard(
                emphasis: MevoraCardEmphasis.elevated,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.82,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.relationshipPromptTitle,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          question.promptFor(locale),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        for (final answer in question.answers)
                          if (answer.labelFor(locale).trim().isNotEmpty) ...[
                            MevoraButton(
                              label: answer.labelFor(locale),
                              variant: MevoraButtonVariant.secondary,
                              wrapLabel: true,
                              onPressed: submitting
                                  ? null
                                  : () => onAnswer(answer.id),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        const SizedBox(height: AppSpacing.xs),
                        if (submitting)
                          Padding(
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: MevoraRiveAnimation(
                              asset: MevoraRiveAssets.loading,
                              width: 36,
                              height: 36,
                              semanticsLabel: l10n.loading,
                              fallback: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        if (lastError != null && lastError!.isNotEmpty) ...[
                          Text(
                            lastError!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                        Text(
                          l10n.relationshipPromptProgress(
                            answeredCount.clamp(1, totalCount),
                            totalCount,
                          ),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RelationshipQuestionUnavailableCard extends StatelessWidget {
  const RelationshipQuestionUnavailableCard({
    super.key,
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.elevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.relationshipPromptTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.relationshipQuestionsPreparing,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(label: l10n.close, onPressed: onDismiss),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RelationshipContinueMatchingCard extends StatelessWidget {
  const RelationshipContinueMatchingCard({
    super.key,
    required this.onContinue,
    required this.onNotNow,
  });

  final VoidCallback onContinue;
  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.elevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.relationshipContinueTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.relationshipContinueMessage,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(
                    label: l10n.relationshipContinueYes,
                    onPressed: onContinue,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MevoraButton(
                    label: l10n.relationshipContinueNo,
                    variant: MevoraButtonVariant.secondary,
                    onPressed: onNotNow,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MatchingGameWaitingCard extends StatelessWidget {
  const MatchingGameWaitingCard({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.elevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.matchingGameWaitingTitle,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.matchingGameWaitingMessage,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(
                    label: l10n.matchingGameWaitingDismiss,
                    variant: MevoraButtonVariant.secondary,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RelationshipTestOfferCard extends StatelessWidget {
  const RelationshipTestOfferCard({
    super.key,
    required this.onStart,
    required this.onLater,
    this.roundHour,
    this.countdown,
    this.isInitial = false,
  });

  final VoidCallback onStart;
  final VoidCallback onLater;
  final String? roundHour;
  final Duration? countdown;
  final bool isInitial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hour = roundHour;
    final String headline;
    final String message;
    final String startLabel;
    final String titleSemantics;
    if (isInitial) {
      headline = l10n.relationshipInitialTestHeadline;
      message = l10n.relationshipInitialTestMessage;
      startLabel = l10n.relationshipInitialTestStart;
      titleSemantics = l10n.relationshipInitialTestTitle;
    } else if (hour != null && hour.isNotEmpty) {
      headline = l10n.mevoraHourRoundLabel(hour);
      message = l10n.mevoraHourMessage;
      startLabel = l10n.mevoraHourJoin;
      titleSemantics = l10n.mevoraHourTitle;
    } else {
      headline = l10n.mevoraHourHeadline;
      message = l10n.mevoraHourMessage;
      startLabel = l10n.mevoraHourJoin;
      titleSemantics = l10n.mevoraHourTitle;
    }
    final remain = countdown;
    String? countdownLabel;
    if (!isInitial && remain != null) {
      final h = remain.inHours;
      final m = remain.inMinutes.remainder(60);
      final s = remain.inSeconds.remainder(60);
      final padded =
          '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
      countdownLabel = l10n.mevoraHourCountdown(padded);
    }
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.elevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: MevoraRiveAnimation(
                      asset: MevoraRiveAssets.relationshipResult,
                      width: 48,
                      height: 48,
                      semanticsLabel: titleSemantics,
                      fallback: Icon(
                        Icons.favorite_outline,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!isInitial) ...[
                    Text(
                      l10n.mevoraHourTitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                    headline,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    message,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (countdownLabel != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      countdownLabel,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  MevoraButton(
                    label: startLabel,
                    onPressed: onStart,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MevoraButton(
                    label: l10n.relationshipTestLater,
                    variant: MevoraButtonVariant.secondary,
                    onPressed: onLater,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RelationshipTestResultCard extends StatelessWidget {
  const RelationshipTestResultCard({
    super.key,
    required this.results,
    required this.onDismiss,
    this.onAcceptMatch,
    this.empty = false,
  });

  final List<RelationshipMatchSuggestion> results;
  final VoidCallback onDismiss;
  final VoidCallback? onAcceptMatch;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.42),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.elevated,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: MevoraRiveAnimation(
                      asset: MevoraRiveAssets.relationshipResult,
                      width: 48,
                      height: 48,
                      semanticsLabel: l10n.relationshipTestDoneTitle,
                      fallback: Icon(
                        Icons.favorite,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    l10n.relationshipTestDoneTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    empty
                        ? l10n.relationshipTestEmpty
                        : l10n.relationshipTestFound,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (!empty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.relationshipTestAlign,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.relationshipTestNearest,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    if (results.isNotEmpty)
                      _ResultTile(suggestion: results.first),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  if (!empty && results.isNotEmpty) ...[
                    MevoraButton(
                      label: l10n.relationshipTestViewProfile,
                      onPressed: () => _openProfile(context, results.first),
                    ),
                    if (results.first.matchId != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      MevoraButton(
                        label: l10n.relationshipTestOpenChat,
                        variant: MevoraButtonVariant.secondary,
                        onPressed: () {
                          final matchId = results.first.matchId;
                          // Match taken → 30 min survey pause (do not call onDismiss).
                          (onAcceptMatch ?? onDismiss)();
                          if (matchId != null) {
                            context.go(AppRoutes.chatPath(matchId));
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  MevoraButton(
                    label: l10n.close,
                    variant: empty
                        ? MevoraButtonVariant.primary
                        : MevoraButtonVariant.secondary,
                    onPressed: onDismiss,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openProfile(
  BuildContext context,
  RelationshipMatchSuggestion suggestion,
) {
  unawaited(
    Navigator.of(context).push(
      MevoraPageTransitions.route<void>(
        builder: (_) =>
            DiscoveryProfileDetailsPage(candidate: suggestion.candidate),
      ),
    ),
  );
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.suggestion});

  final RelationshipMatchSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final candidate = suggestion.candidate;
    final distance =
        candidate.distanceLabel ??
        (candidate.distanceKm == null
            ? null
            : '${candidate.distanceKm} km');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _openProfile(context, suggestion),
      leading: MevoraAvatar(
        name: candidate.displayName,
        image: MevoraNetworkImages.provider(candidate.photoUrl),
        size: 48,
      ),
      title: Text(candidate.displayName),
      subtitle: Text(distance ?? candidate.city ?? ''),
    );
  }
}
