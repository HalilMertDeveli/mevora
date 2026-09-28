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
import 'package:mevora/shared/art/mevora_spot.dart';
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
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 64,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.matchesTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineMedium,
                ),
                Text(
                  l10n.matchesSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
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
                      art: MevoraArt.emptyMatches,
                      title: l10n.matchesEmptyTitle,
                      message: l10n.matchesEmptyMessage,
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                  children: [
                    LikesYouEntryCard(
                      onTap: () => context.push(AppRoutes.likesYou),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    for (var i = 0; i < controller.items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          indent: AppSpacing.md + 56 + AppSpacing.s12 + 2,
                          endIndent: AppSpacing.md,
                        ),
                      MatchConnectionTile(
                        item: controller.items[i],
                        currentUid: uid,
                        breakdown: controller.items[i].breakdown,
                        showOnlineIndicator:
                            controller.presenceFor(
                              controller.items[i].otherUserId,
                            ) ==
                            PresenceStatus.online,
                        onTap: () => context.push(
                          AppRoutes.chatPath(controller.items[i].match.id),
                        ),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

/// Legacy export kept for tests referencing [MatchListTile].
typedef MatchListTile = MatchConnectionTile;
