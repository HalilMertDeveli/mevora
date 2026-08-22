import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/matching/domain/models/match_list_item.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class MatchListTile extends StatelessWidget {
  const MatchListTile({
    super.key,
    required this.item,
    required this.currentUid,
    this.onTap,
  });

  final MatchListItem item;
  final String currentUid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final unread = item.unreadCount(currentUid);
    final isNew = item.showNewMatchBadge;
    final photo = item.photoUrl;
    return ListTile(
      onTap: onTap,
      leading: MevoraAvatar(
        name: item.name,
        image: MevoraNetworkImages.provider(photo),
        size: 56,
      ),
      title: Text(item.name, style: theme.textTheme.titleMedium),
      subtitle: Text(
        [
          if (item.match.isRelationshipTest) l10n.relationshipMatchBadge,
          isNew ? l10n.newMatch : (item.match.lastMessage ?? ''),
        ].where((part) => part.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            L10nFormat.compactDate(
              l10n,
              item.match.lastMessageAt ?? item.match.createdAt,
            ),
            style: theme.textTheme.labelSmall,
          ),
          if (unread > 0) ...[
            const SizedBox(height: 6),
            CircleAvatar(
              radius: 10,
              child: Text('$unread', style: theme.textTheme.labelSmall),
            ),
          ] else if (isNew) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(l10n.newMatch, style: theme.textTheme.labelSmall),
            ),
          ],
        ],
      ),
    );
  }
}

class MatchesRoutePage extends StatelessWidget {
  const MatchesRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.maybeOf(context);
    if (social == null) {
      return Scaffold(
        body: MevoraEmptyState(
          message: AppLocalizations.of(context).needSignIn,
        ),
      );
    }
    return MatchesPage(controller: social.matchesController);
  }
}

class MatchesPage extends StatelessWidget {
  const MatchesPage({super.key, required this.controller});

  final MatchesController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uid = controller.uid;
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(title: Text(l10n.matchesTitle)),
          body: uid == null
              ? MevoraEmptyState(message: l10n.needSignIn)
              : controller.loading
              ? MevoraLoading.page(message: l10n.matchesTitle)
              : controller.error != null
              ? MevoraErrorView(
                  message: controller.error,
                  onRetry: controller.start,
                )
              : controller.items.isEmpty
              ? MevoraEmptyState(
                  icon: Icons.favorite_outline,
                  riveAsset: MevoraRiveAssets.emptyMatches,
                  title: l10n.matchesEmptyTitle,
                  message: l10n.matchesEmptyMessage,
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    ...controller.items.map(
                      (item) => MatchListTile(
                        item: item,
                        currentUid: uid,
                        onTap: () =>
                            context.push(AppRoutes.chatPath(item.match.id)),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
