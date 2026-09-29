import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/match_score/presentation/widgets/match_feedback_prompt.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/features/streak/presentation/widgets/streak_celebration.dart';
import 'package:mevora/l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _tabLabels = ['Discover', 'Matches', 'Music', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final social = SocialScope.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final matches = social?.matchesController;

    final Widget body = IncomingCallNavigator(
      child: MatchFeedbackHost(
        child: StreakCelebrationHost(child: navigationShell),
      ),
    );

    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border(top: BorderSide(color: context.palette.divider)),
        ),
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
          destinations: [
            NavigationDestination(
              icon: const Icon(MevoraIcons.discover),
              selectedIcon: const Icon(MevoraIcons.discoverActive),
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
              icon: const Icon(MevoraIcons.music),
              selectedIcon: const Icon(MevoraIcons.musicActive),
              label: l10n.tabMusic,
            ),
            NavigationDestination(
              icon: const Icon(MevoraIcons.profile),
              selectedIcon: const Icon(MevoraIcons.profileActive),
              label: l10n.tabProfile,
            ),
          ],
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
    final fromLabel = from >= 0 && from < _tabLabels.length
        ? _tabLabels[from]
        : '$from';
    final toLabel = to >= 0 && to < _tabLabels.length ? _tabLabels[to] : '$to';
    // ignore: avoid_print
    print('[TAB] changed: $fromLabel → $toLabel | uid=${uid ?? 'none'}');
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
    final icon = Icon(
      selected ? MevoraIcons.matchesActive : MevoraIcons.matches,
    );
    final matches = matchesController;
    if (matches == null) {
      return icon;
    }
    return AnimatedBuilder(
      animation: matches,
      builder: (context, _) {
        final unread = matches.totalUnread;
        final scheme = Theme.of(context).colorScheme;
        return Badge(
          isLabelVisible: unread > 0,
          backgroundColor: scheme.primary,
          textColor: scheme.onPrimary,
          label: Text(unread > 99 ? '99+' : '$unread'),
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
