import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/features/relationship/presentation/controllers/relationship_controller.dart';
import 'package:mevora/features/relationship/presentation/widgets/relationship_question_card.dart';
import 'package:mevora/l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabLabels = ['Discover', 'Matches', 'Music', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final relationship = RelationshipScope.controllerOf(context);
    final matches = social?.matchesController;

    Widget body = IncomingCallNavigator(
      child: MatchFeedbackHost(child: navigationShell),
    );
    if (relationship != null) {
      body = _ShellRelationshipBridge(
        controller: relationship,
        discoveryVisible: navigationShell.currentIndex == 0,
        matchesController: matches,
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
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final isDark = theme.brightness == Brightness.dark;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.glassFill
                    : AppColors.lightGlassFill,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(
                  color: isDark
                      ? AppColors.glassBorder
                      : AppColors.lightGlassBorder,
                ),
                boxShadow: isDark
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                child: NavigationBar(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: (index) {
                    _logTabChange(
                      from: navigationShell.currentIndex,
                      to: index,
                      uid: social?.uidSource.currentUid,
                    );
                    navigationShell.goBranch(index);
                  },
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  destinations: [
                    NavigationDestination(
                      icon: const Icon(Icons.explore_outlined),
                      selectedIcon: const Icon(Icons.explore),
                      label: l10n.tabDiscovery,
                    ),
                    NavigationDestination(
                      icon: _UnreadMatchesIcon(
                        matchesController: matches,
                        selected: false,
                      ),
                      selectedIcon: _UnreadMatchesIcon(
                        matchesController: matches,
                        selected: true,
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
            );
          },
        ),
      ),
    );
  }

  static void _logTabChange({
    required int from,
    required int to,
    required String? uid,
  }) {
    if (!kDebugMode || from == to) {
      return;
    }
    final fromLabel =
        from >= 0 && from < _tabLabels.length ? _tabLabels[from] : '$from';
    final toLabel =
        to >= 0 && to < _tabLabels.length ? _tabLabels[to] : '$to';
    // ignore: avoid_print
    print(
      '[TAB] changed: $fromLabel → $toLabel | uid=${uid ?? 'none'}',
    );
  }
}

/// Keeps relationship dwell visibility in sync with the shell tab index.
///
/// Presence ticks only rebuild this thin bridge (via [AnimatedBuilder]), not
/// the bottom [NavigationBar] or an unnecessary full-shell [setState].
class _ShellRelationshipBridge extends StatelessWidget {
  const _ShellRelationshipBridge({
    required this.controller,
    required this.discoveryVisible,
    required this.child,
    this.matchesController,
  });

  final RelationshipController controller;
  final bool discoveryVisible;
  final MatchesController? matchesController;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final matches = matchesController;
    if (matches == null) {
      return RelationshipDiscoverySync(
        controller: controller,
        discoveryVisible: discoveryVisible,
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: matches,
      builder: (context, _) {
        return RelationshipDiscoverySync(
          controller: controller,
          discoveryVisible: discoveryVisible,
          normalMatchCount: matches.activeConversationCount,
          child: child,
        );
      },
    );
  }
}

class _UnreadMatchesIcon extends StatelessWidget {
  const _UnreadMatchesIcon({
    required this.matchesController,
    required this.selected,
  });

  final MatchesController? matchesController;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.favorite : Icons.favorite_outline);
    final matches = matchesController;
    if (matches == null) {
      return icon;
    }
    return AnimatedBuilder(
      animation: matches,
      builder: (context, _) {
        final unread = matches.totalUnread;
        return Badge(
          isLabelVisible: unread > 0,
          label: Text('$unread'),
          child: icon,
        );
      },
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
