import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';
import 'package:mevora/features/calls/presentation/controllers/call_controller.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';
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
    required this.incomingLikesRepository,
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
  final IncomingLikesRepository incomingLikesRepository;
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

class SocialScopeState extends State<SocialScope> with WidgetsBindingObserver {
  late final MatchesController matchesController;
  late final CallController callController;
  StreamSubscription<String?>? _uidSub;
  String? _boundUid;

  MatchRepository get matchRepository => widget.services.matchRepository;
  LikeRepository get likeRepository => widget.services.likeRepository;
  ChatRepository get chatRepository => widget.services.chatRepository;
  SafetyRepository get safetyRepository => widget.services.safetyRepository;
  PresenceRepository get presenceRepository =>
      widget.services.presenceRepository;
  AuthUidSource get uidSource => widget.services.uidSource;
  NotificationRepository get notificationRepository =>
      widget.services.notificationRepository;
  IncomingLikesRepository get incomingLikesRepository =>
      widget.services.incomingLikesRepository;
  ChatRetentionPolicy get retentionPolicy => widget.services.retentionPolicy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    matchesController = MatchesController(
      matchRepository: widget.services.matchRepository,
      presenceRepository: widget.services.presenceRepository,
      uidSource: widget.services.uidSource,
    )..start();
    callController = CallController(
      service: widget.services.videoCallService,
      provider: widget.services.videoCallProvider,
    );
    _boundUid = widget.services.uidSource.currentUid;
    _uidSub = widget.services.uidSource.watchUid().listen((uid) {
      _onUid(uid);
    }, onError: (_) {
      _onUid(widget.services.uidSource.currentUid);
    });
    final uid = _boundUid;
    if (uid != null) {
      callController.watchIncoming(uid);
    }
  }

  void _onUid(String? uid) {
    if (uid == _boundUid) {
      return;
    }
    debugPrint(
      '[TAB] social uid changed: ${_boundUid ?? 'none'} → ${uid ?? 'none'} '
      '| restarting matches/incoming listeners',
    );
    _boundUid = uid;
    matchesController.start();
    if (uid != null) {
      callController.watchIncoming(uid);
    } else {
      callController.stopIncoming();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      matchesController.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
