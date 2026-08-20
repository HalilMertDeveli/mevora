import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/presentation/widgets/boost_active_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
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
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const IgnorePointer(
                  child: Opacity(
                    opacity: 0.55,
                    child: MevoraRiveAnimation(
                      asset: MevoraRiveAssets.profileAccent,
                      width: 168,
                      height: 168,
                      fit: BoxFit.contain,
                      fallback: SizedBox.shrink(),
                    ),
                  ),
                ),
                MevoraAvatar(
                  name: user?.displayName ?? l10n.appName,
                  image: user?.photoUrl == null
                      ? null
                      : NetworkImage(user!.photoUrl!),
                  size: 96,
                ),
              ],
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
          const _ProfileBoostTile(),
          _ProfileTile(
            icon: Icons.edit_outlined,
            title: l10n.editProfile,
            onTap: () => context.push(AppRoutes.editProfile),
          ),
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

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

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
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
