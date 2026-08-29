import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/matching/domain/models/presence_status.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/features/matching/presentation/widgets/likes_you_insight_card.dart';
import 'package:mevora/features/matching/presentation/widgets/match_connection_tile.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

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

class MatchesPage extends StatefulWidget {
  const MatchesPage({super.key, required this.controller});

  final MatchesController controller;

  @override
  State<MatchesPage> createState() => _MatchesPageState();
}

class _MatchesPageState extends State<MatchesPage> {
  Timer? _elapsedTicker;

  @override
  void initState() {
    super.initState();
    _elapsedTicker = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _elapsedTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final uid = controller.uid;
        final l10n = AppLocalizations.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.matchesTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  l10n.matchesSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
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
              ? ListView(
                  children: [
                    LikesYouEntryCard(
                      onTap: () => context.push(AppRoutes.likesYou),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    MevoraEmptyState(
                      icon: Icons.insights_outlined,
                      riveAsset: MevoraRiveAssets.emptyMatches,
                      title: l10n.matchesEmptyTitle,
                      message: l10n.matchesEmptyMessage,
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  children: [
                    LikesYouEntryCard(
                      onTap: () => context.push(AppRoutes.likesYou),
                    ),
                    ...controller.items.map(
                      (item) => MatchConnectionTile(
                        item: item,
                        currentUid: uid,
                        breakdown: item.breakdown,
                        showOnlineIndicator:
                            controller.presenceFor(item.otherUserId) ==
                            PresenceStatus.online,
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

/// Legacy export kept for tests referencing [MatchListTile].
typedef MatchListTile = MatchConnectionTile;
