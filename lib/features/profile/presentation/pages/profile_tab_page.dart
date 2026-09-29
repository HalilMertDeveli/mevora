import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/subscription_scope.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/features/verification/domain/entities/identity_verification.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_active_badge.dart';
import 'package:mevora/features/verification/presentation/widgets/verification_entry_tile.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

class ProfileTabPage extends StatelessWidget {
  const ProfileTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = AuthScope.maybeOf(context)?.user;
    final theme = Theme.of(context);
    final humorEnabled =
        AppScope.maybeOf(context)?.config.featureFlags.humorLabEnabled == true;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile, style: theme.textTheme.headlineMedium),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(MevoraIcons.settings),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.sm,
          AppSpacing.screenPadding,
          AppSpacing.xxl,
        ),
        children: [
          // Identity: the portrait, the name, one clear action.
          Center(
            child: MevoraAvatar(
              name: user?.displayName ?? l10n.appName,
              image: MevoraNetworkImages.provider(user?.photoUrl),
              size: 112,
              isVerified: user?.isVerified ?? false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            user?.displayName ?? l10n.profile,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineLarge,
          ),
          if (user?.email != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              user!.email!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Center(
            child: MevoraButton(
              label: l10n.editProfile,
              icon: MevoraIcons.edit,
              variant: MevoraButtonVariant.secondary,
              size: MevoraButtonSize.small,
              isExpanded: false,
              onPressed: () => context.push(AppRoutes.editProfile),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ProfilePremiumTile(),
          if (user?.id != null) ...[
            ProfileQuestionAnswersSection(
              uid: user!.id,
              isOwner: true,
              showEditAction: true,
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          MevoraListGroup(
            title: l10n.profileSectionSignals,
            children: [
              MevoraListRow(
                icon: MevoraIcons.musicActive,
                iconTone: MevoraTone.music,
                title: l10n.musicTitle,
                onTap: () => context.go(AppRoutes.music),
              ),
              // Entry point for anyone who skipped calibration, or who
              // predates it entirely. Existing users are never pushed back
              // through onboarding — they start from here, voluntarily.
              if (humorEnabled) const _HumorProfileTile(),
              const _ProfileRelationshipTile(),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          MevoraListGroup(
            title: l10n.profileSectionTrust,
            children: const [
              _ProfileVerificationTile(),
              _ProfileBoostTile(),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileVerificationTile extends StatefulWidget {
  const _ProfileVerificationTile();

  @override
  State<_ProfileVerificationTile> createState() =>
      _ProfileVerificationTileState();
}

class _ProfileVerificationTileState extends State<_ProfileVerificationTile> {
  StreamSubscription<IdentityVerification>? _subscription;
  IdentityVerificationStatus _status = IdentityVerificationStatus.notStarted;
  String? _subscribedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = VerificationScope.maybeOf(context);
    if (uid == null || repository == null || uid == _subscribedUid) {
      return;
    }
    _subscribedUid = uid;
    unawaited(_subscription?.cancel());
    _subscription = repository
        .watchVerification(uid)
        .listen(
          (value) {
            if (!mounted) {
              return;
            }
            setState(() => _status = value.status);
          },
          onError: (_, _) {
            if (!mounted) {
              return;
            }
            setState(() => _status = IdentityVerificationStatus.notStarted);
          },
        );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthScope.maybeOf(context)?.user;
    return VerificationEntryTile(
      status: _status,
      accountVerified: user?.isVerified ?? false,
    );
  }
}

class _ProfileBoostTile extends StatefulWidget {
  const _ProfileBoostTile();

  @override
  State<_ProfileBoostTile> createState() => _ProfileBoostTileState();
}

class _ProfileBoostTileState extends State<_ProfileBoostTile> {
  Boost? _boost;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final scope = BoostScope.maybeOf(context);
    final uid = AuthScope.maybeOf(context)?.user?.id;
    if (scope == null || uid == null) {
      return;
    }
    final result = await scope.repository.getActiveBoost(uid);
    if (!mounted) {
      return;
    }
    setState(() => _boost = result.valueOrNull);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final active = _boost != null && _boost!.isActiveAt(DateTime.now());
    return MevoraListRow(
      icon: active ? MevoraIcons.boostActive : MevoraIcons.boost,
      iconTone: MevoraTone.accent,
      title: l10n.boostSpotlight,
      trailing: active ? BoostActiveBadge(boost: _boost, compact: true) : null,
      onTap: () => context.push(AppRoutes.boost),
    );
  }
}

/// Entry point to the paywall, and the Premium badge once it is active.
///
/// Hidden entirely when the app was wired without billing — Premium off, or
/// a build with no store. Nothing here decides entitlement; it reads the
/// server-written status the same way every other gate does.
class _ProfilePremiumTile extends StatelessWidget {
  const _ProfilePremiumTile();

  @override
  Widget build(BuildContext context) {
    if (SubscriptionScope.billingOf(context) == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final isPremium = SubscriptionScope.isPremiumOf(context);
    final theme = Theme.of(context);
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: MevoraCard(
        color: p.premiumSurface,
        onTap: () => context.push(AppRoutes.premium),
        semanticLabel: l10n.premiumTitle,
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: p.premium, width: 1.5),
              ),
              child: Icon(
                isPremium ? MevoraIcons.premiumActive : MevoraIcons.premium,
                color: p.premium,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.premiumTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: p.onPremiumSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    isPremium
                        ? l10n.premiumAlreadyActive
                        : l10n.premiumSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: p.onPremiumSurface.withValues(alpha: 0.78),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              MevoraIcons.chevronRight,
              color: p.onPremiumSurface.withValues(alpha: 0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileRelationshipTile extends StatelessWidget {
  const _ProfileRelationshipTile();

  @override
  Widget build(BuildContext context) {
    final controller = RelationshipScope.controllerOf(context);
    if (controller == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return MevoraListRow(
          icon: MevoraIcons.questions,
          iconTone: MevoraTone.compatibility,
          title: l10n.relationshipMatchesTitle,
          subtitle: l10n.relationshipProfileSubtitle(controller.answeredCount),
          onTap: () => context.go(AppRoutes.matches),
        );
      },
    );
  }
}

/// Humor entry that reflects where the user actually is.
///
/// Reads calibration state from the server rather than assuming: a user who
/// calibrated on another device should see "ready", not an invitation to
/// start over. Failure degrades to the plain invitation rather than hiding
/// the feature.
class _HumorProfileTile extends StatefulWidget {
  const _HumorProfileTile();

  @override
  State<_HumorProfileTile> createState() => _HumorProfileTileState();
}

class _HumorProfileTileState extends State<_HumorProfileTile> {
  HumorCalibration? _calibration;
  var _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) {
      return;
    }
    _requested = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = HumorScope.maybeOf(context);
    if (repository == null) {
      return;
    }
    final result = await repository.getProfile();
    if (!mounted) {
      return;
    }
    setState(
      () => _calibration = result.valueOrNull?.calibration ?? _calibration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final calibration = _calibration;

    final String subtitle;
    if (calibration == null || !calibration.started) {
      subtitle = l10n.humorProfileEntryNotStarted;
    } else if (calibration.complete) {
      subtitle = l10n.humorProfileEntryComplete;
    } else {
      subtitle = l10n.humorProfileEntryInProgress(
        calibration.completedCount,
        calibration.totalCount,
      );
    }

    return MevoraListRow(
      icon: MevoraIcons.humorActive,
      iconTone: MevoraTone.humor,
      title: l10n.humorLabTitle,
      subtitle: subtitle,
      // An unfinished calibration resumes through the invitation screen so the
      // user sees where they are before being dropped back into content.
      onTap: () => unawaited(_open(calibration?.complete == true)),
    );
  }

  Future<void> _open(bool complete) async {
    await context.push(
      complete ? AppRoutes.humorLab : AppRoutes.humorCalibration,
    );
    if (mounted) {
      // The profile tab stays alive underneath: show the progress made.
      await _load();
    }
  }
}
