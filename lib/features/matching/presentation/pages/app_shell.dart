import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/relationship_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/match_score/presentation/widgets/match_feedback_prompt.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.maybeOf(context);
    Widget shell(int unread) {
      final l10n = AppLocalizations.of(context);
      final relationship = RelationshipScope.controllerOf(context);
      Widget body = IncomingCallNavigator(
        child: MatchFeedbackHost(child: navigationShell),
      );
      if (relationship != null) {
        body = RelationshipDiscoverySync(
          controller: relationship,
          discoveryVisible: navigationShell.currentIndex == 0,
          normalMatchCount: social?.matchesController.mutualLikeCount ?? 0,
          child: body,
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.glassFill,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.xl),
              child: NavigationBar(
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: navigationShell.goBranch,
                backgroundColor: Colors.transparent,
                elevation: 0,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.explore_outlined),
                    selectedIcon: const Icon(Icons.explore),
                    label: l10n.tabDiscovery,
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.favorite_outline),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: unread > 0,
                      label: Text('$unread'),
                      child: const Icon(Icons.favorite),
                    ),
                    label: l10n.tabMatches,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.library_music_outlined),
                    selectedIcon: const Icon(Icons.library_music),
                    label: l10n.tabMusic,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.person_outline),
                    selectedIcon: const Icon(Icons.person),
                    label: l10n.tabProfile,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (social == null) {
      return shell(0);
    }
    return AnimatedBuilder(
      animation: social.matchesController,
      builder: (context, _) => shell(social.matchesController.totalUnread),
    );
  }
}

class IncomingCallNavigator extends StatefulWidget {
  const IncomingCallNavigator({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingCallNavigator> createState() => _IncomingCallNavigatorState();
}

class _IncomingCallNavigatorState extends State<IncomingCallNavigator> {
  String? _openedCallId;

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.maybeOf(context);
    if (social == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: social.callController,
      builder: (context, _) {
        final session = social.callController.session;
        final lifecycle = social.callController.lifecycle;
        if (lifecycle == CallLifecycle.ringing &&
            session != null &&
            session.id.isNotEmpty &&
            session.id != _openedCallId) {
          final callId = session.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _openedCallId == callId) {
              return;
            }
            setState(() => _openedCallId = callId);
            final path = GoRouterState.of(context).uri.path;
            if (path.contains('/call/')) {
              return;
            }
            unawaited(context.push(AppRoutes.incomingCallPath(callId)));
          });
        }
        return widget.child;
      },
    );
  }
}
