import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/controllers/call_controller.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/domain/repositories/match_repository.dart';
import 'package:mevora/features/matching/presentation/controllers/matches_controller.dart';
import 'package:mevora/features/notifications/domain/models/notification_prefs.dart';
import 'package:mevora/features/safety/domain/safety_policy.dart';

class SocialServices {
  const SocialServices({
    required this.uidSource,
    required this.matchRepository,
    required this.likeRepository,
    required this.chatRepository,
    required this.safetyRepository,
    required this.presenceRepository,
    required this.callRepository,
    required this.videoCallService,
    required this.videoCallProvider,
    required this.notificationRepository,
    required this.discoveryExclusion,
    this.retentionPolicy = const NoOpChatRetentionPolicy(),
  });

  final AuthUidSource uidSource;
  final MatchRepository matchRepository;
  final LikeRepository likeRepository;
  final ChatRepository chatRepository;
  final SafetyRepository safetyRepository;
  final PresenceRepository presenceRepository;
  final CallRepository callRepository;
  final VideoCallService videoCallService;
  final VideoCallProvider videoCallProvider;
  final NotificationRepository notificationRepository;
  final DiscoveryExclusionSource discoveryExclusion;
  final ChatRetentionPolicy retentionPolicy;
}

class SocialScope extends StatefulWidget {
  const SocialScope({
    super.key,
    required this.services,
    required this.child,
  });

  final SocialServices services;
  final Widget child;

  static SocialScopeState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_SocialScope>();
    assert(scope != null, 'SocialScope not found');
    return scope!.state;
  }

  static SocialScopeState? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_SocialScope>()?.state;
  }

  @override
  State<SocialScope> createState() => SocialScopeState();
}

class SocialScopeState extends State<SocialScope> {
  late final MatchesController matchesController;
  late final CallController callController;
  StreamSubscription<String?>? _uidSub;

  MatchRepository get matchRepository => widget.services.matchRepository;
  LikeRepository get likeRepository => widget.services.likeRepository;
  ChatRepository get chatRepository => widget.services.chatRepository;
  SafetyRepository get safetyRepository => widget.services.safetyRepository;
  PresenceRepository get presenceRepository =>
      widget.services.presenceRepository;
  AuthUidSource get uidSource => widget.services.uidSource;
  NotificationRepository get notificationRepository =>
      widget.services.notificationRepository;
  ChatRetentionPolicy get retentionPolicy => widget.services.retentionPolicy;

  @override
  void initState() {
    super.initState();
    matchesController = MatchesController(
      matchRepository: widget.services.matchRepository,
      presenceRepository: widget.services.presenceRepository,
      uidSource: widget.services.uidSource,
    )..start();
    callController = CallController(
      service: widget.services.videoCallService,
      provider: widget.services.videoCallProvider,
    );
    _uidSub = widget.services.uidSource.watchUid().listen((uid) {
      matchesController.start();
      if (uid != null) {
        callController.watchIncoming(uid);
      } else {
        callController.stopIncoming();
      }
    }, onError: (_) {
      matchesController.start();
      callController.stopIncoming();
    });
    final uid = widget.services.uidSource.currentUid;
    if (uid != null) {
      callController.watchIncoming(uid);
    }
  }

  @override
  void dispose() {
    unawaited(_uidSub?.cancel());
    matchesController.dispose();
    callController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    matchesController.attachSettingsHub(
      SettingsScope.maybeOf(context)?.settingsHub,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SocialScope(state: this, child: widget.child);
  }
}

class _SocialScope extends InheritedWidget {
  const _SocialScope({required this.state, required super.child});

  final SocialScopeState state;

  @override
  bool updateShouldNotify(_SocialScope oldWidget) => oldWidget.state != state;
}
