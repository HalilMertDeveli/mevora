import 'package:mevora/core/routing/app_routes.dart';

/// Maps FCM data payloads to in-app routes. No sensitive content.
abstract final class PushRouteResolver {
  static String? fromData(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    final matchId = data['matchId']?.toString();
    final callId = data['callId']?.toString();
    switch (type) {
      case 'incomingCall':
      case 'incoming_call':
        if (callId == null || callId.isEmpty) {
          return null;
        }
        return AppRoutes.incomingCallPath(callId);
      case 'newMessage':
      case 'message':
      case 'newPhoto':
      case 'newVoice':
      case 'newMatch':
      case 'match':
      case 'missedCall':
      case 'missed_call':
        if (matchId == null || matchId.isEmpty) {
          return null;
        }
        return AppRoutes.chatPath(matchId);
      case 'boostActivated':
      case 'boostExpired':
        return AppRoutes.boost;
      case 'supportReply':
        // A staff reply to the member's own request. Without an id the list
        // is the honest destination.
        final ticketId = data['ticketId']?.toString();
        if (ticketId == null || ticketId.isEmpty) {
          return AppRoutes.supportTickets;
        }
        return AppRoutes.supportTicketDetailPath(ticketId);
      default:
        return null;
    }
  }
}
