import 'package:mevora/core/di/demo_social_hub.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/identity/firebase_auth_uid_source.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/calls/data/providers/mock_video_call_provider.dart';
import 'package:mevora/features/calls/data/services/video_call_service_impl.dart';
import 'package:mevora/features/matching/data/firebase/firebase_social_data.dart';
import 'package:mevora/features/matching/data/memory/graph_repositories.dart';
import 'package:mevora/features/matching/data/memory/in_memory_social_graph.dart';
import 'package:mevora/features/matching/data/overlay/overlay_social_repositories.dart';

SocialServices createGraphSocialServices({
  required InMemorySocialGraph graph,
  required AuthUidSource uidSource,
  MockVideoCallProvider? videoProvider,
}) {
  final provider = videoProvider ?? MockVideoCallProvider();
  final calls = GraphCallRepository(graph, uidSource);
  return SocialServices(
    uidSource: uidSource,
    matchRepository: GraphMatchRepository(graph, uidSource),
    likeRepository: GraphMatchRepository(graph, uidSource),
    chatRepository: GraphChatRepository(graph, uidSource),
    safetyRepository: GraphSafetyRepository(graph, uidSource),
    presenceRepository: GraphPresenceRepository(graph),
    callRepository: calls,
    videoCallService: VideoCallServiceImpl(calls),
    videoCallProvider: provider,
    notificationRepository: GraphNotificationRepository(graph),
    discoveryExclusion: GraphMatchRepository(graph, uidSource),
  );
}

SocialServices createFirebaseSocialServices({
  AuthUidSource? uidSource,
  DemoSocialHub? demoHub,
}) {
  final uid = uidSource ?? demoHub?.uidSource ?? FirebaseAuthUidSource();
  final callable = FirebaseFunctionsCallable();
  final matches = FirebaseMatchRepository(callable: callable, uidSource: uid);
  final chat = FirebaseChatRepository(uidSource: uid);
  final calls = FirebaseCallRepository(callable: callable, uidSource: uid);
  return SocialServices(
    uidSource: uid,
    matchRepository: demoHub == null
        ? matches
        : OverlayMatchRepository(remote: matches, hub: demoHub),
    likeRepository: matches,
    chatRepository: demoHub == null
        ? chat
        : OverlayChatRepository(remote: chat, hub: demoHub),
    safetyRepository: demoHub == null
        ? FirebaseSafetyRepository(
            callable: callable,
            uidSource: uid,
          )
        : OverlaySafetyRepository(
            remote: FirebaseSafetyRepository(
              callable: callable,
              uidSource: uid,
            ),
            hub: demoHub,
          ),
    presenceRepository: FirebasePresenceRepository(),
    callRepository: calls,
    videoCallService: VideoCallServiceImpl(calls),
    videoCallProvider: MockVideoCallProvider(),
    notificationRepository: FirebaseNotificationRepository(),
    discoveryExclusion: matches,
  );
}
