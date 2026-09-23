import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/match_score_scope.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/verification_scope.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_active_badge.dart';
import 'package:mevora/features/match_score/presentation/widgets/match_score_tile.dart';
import 'package:mevora/features/verification/presentation/widgets/verification_entry_tile.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';

class ProfileTabPage extends StatelessWidget {
  const ProfileTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final user = AuthScope.maybeOf(context)?.user;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.profile),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            onPressed: () => context.push(AppRoutes.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          Center(
            child: MevoraAvatar(
              name: user?.displayName ?? l10n.appName,
              image: MevoraNetworkImages.provider(user?.photoUrl),
              size: 96,
              isVerified: user?.isVerified ?? false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            user?.displayName ?? l10n.profile,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
          if (user?.email != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              user!.email!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          if (user?.id != null) ...[
            ProfileQuestionAnswersSection(
              uid: user!.id,
              isOwner: true,
              showEditAction: true,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
          const _ProfileVerificationTile(),
          const _ProfileBoostTile(),
          const _ProfileMatchScoreTile(),
          const _ProfileRelationshipTile(),
          _ProfileTile(
            icon: Icons.edit_outlined,
            title: l10n.editProfile,
            onTap: () => context.push(AppRoutes.editProfile),
          ),
          _ProfileTile(
            icon: Icons.library_music_outlined,
            title: l10n.musicTitle,
            onTap: () => context.go(AppRoutes.music),
          ),
          if (AppScope.maybeOf(context)?.config.featureFlags.humorLabEnabled ==
              true)
            // Entry point for anyone who skipped calibration, or who predates
            // it entirely. Existing users are never pushed back through
            // onboarding — they start from here, voluntarily.
            const _HumorProfileTile(),
          _ProfileTile(
            icon: Icons.tune_rounded,
            title: l10n.discoveryPreferences,
            onTap: () => context.push(AppRoutes.discoveryPreferences),
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            title: l10n.notificationsTitle,
            onTap: () => context.push(AppRoutes.notificationSettings),
          ),
          _ProfileTile(
            icon: Icons.privacy_tip_outlined,
            title: l10n.privacyPermissionsTitle,
            onTap: () => context.push(AppRoutes.privacyPermissions),
          ),
          _ProfileTile(
            icon: Icons.settings_outlined,
            title: l10n.settings,
            onTap: () => context.push(AppRoutes.settings),
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
  StreamSubscription<ProfileVerification>? _subscription;
  ProfileVerificationStatus _status = ProfileVerificationStatus.notStarted;
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
    _subscription = repository.watchVerification(uid).listen(
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
        setState(() => _status = ProfileVerificationStatus.notStarted);
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

class _ProfileMatchScoreTile extends StatelessWidget {
  const _ProfileMatchScoreTile();

  @override
  Widget build(BuildContext context) {
    final uid = AuthScope.maybeOf(context)?.user?.id;
    final repository = MatchScoreScope.maybeOf(context);
    if (uid == null || repository == null) {
      return const SizedBox.shrink();
    }
    return MatchScoreTile(uid: uid, repository: repository);
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: ListTile(
          leading: const Icon(Icons.bolt_rounded),
          title: Text(l10n.boostSpotlight),
          subtitle: _boost == null ? null : BoostActiveBadge(boost: _boost),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.boost),
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
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: ListTile(
              leading: const Icon(Icons.favorite_outline),
              title: Text(l10n.relationshipMatchesTitle),
              subtitle: Text(
                l10n.relationshipProfileSubtitle(controller.answeredCount),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.matches),
            ),
          ),
        );
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Optional second line, for tiles that carry a state the user cares about.
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
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
    setState(() => _calibration = result.valueOrNull?.calibration);
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

    return _ProfileTile(
      icon: Icons.theater_comedy_outlined,
      title: l10n.humorLabTitle,
      subtitle: subtitle,
      // An unfinished calibration resumes through the invitation screen so the
      // user sees where they are before being dropped back into content.
      onTap: () => context.push(
        calibration?.complete == true
            ? AppRoutes.humorLab
            : AppRoutes.humorCalibration,
      ),
    );
  }
}
