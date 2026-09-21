import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/notifications/domain/push_route_resolver.dart';

void main() {
  test('message and match taps open that chat', () {
    expect(
      PushRouteResolver.fromData({'type': 'message', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
    expect(
      PushRouteResolver.fromData({'type': 'match', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
  });

  test('incoming call tap opens the incoming call screen', () {
    expect(
      PushRouteResolver.fromData({'type': 'incoming_call', 'callId': 'c1'}),
      AppRoutes.incomingCallPath('c1'),
    );
  });

  test('canonical FCM types open the same destinations', () {
    expect(
      PushRouteResolver.fromData({'type': 'newMessage', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
    expect(
      PushRouteResolver.fromData({'type': 'newMatch', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
    expect(
      PushRouteResolver.fromData({'type': 'incomingCall', 'callId': 'c1'}),
      AppRoutes.incomingCallPath('c1'),
    );
    expect(
      PushRouteResolver.fromData({'type': 'missedCall', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
    expect(
      PushRouteResolver.fromData({'type': 'boostActivated'}),
      AppRoutes.boost,
    );
    expect(
      PushRouteResolver.fromData({'type': 'boostExpired'}),
      AppRoutes.boost,
    );
  });

  test('incoming like tap opens Likes You', () {
    // The server sends no liker identity with this push — who liked you is
    // premium-gated behind getIncomingLikes — so the type alone must route.
    expect(
      PushRouteResolver.fromData({'type': 'incomingLike'}),
      AppRoutes.likesYou,
    );
  });

  test('an unknown notification type still routes nowhere', () {
    expect(PushRouteResolver.fromData({'type': 'somethingNew'}), isNull);
    expect(PushRouteResolver.fromData(const {}), isNull);
  });

  test('missed call tap opens the related chat', () {
    expect(
      PushRouteResolver.fromData({'type': 'missed_call', 'matchId': 'a_b'}),
      AppRoutes.chatPath('a_b'),
    );
  });
}
