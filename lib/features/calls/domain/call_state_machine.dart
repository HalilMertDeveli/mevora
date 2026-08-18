import 'package:mevora/features/calls/domain/models/call_session.dart';

abstract final class CallStateMachine {
  static CallLifecycle transition(CallLifecycle current, CallEvent event) {
    return switch ((current, event)) {
      (CallLifecycle.idle, CallEvent.startOutgoing) => CallLifecycle.calling,
      (CallLifecycle.idle, CallEvent.receiveIncoming) => CallLifecycle.ringing,
      (CallLifecycle.calling, CallEvent.remoteAccepted) =>
        CallLifecycle.connecting,
      (CallLifecycle.calling, CallEvent.remoteDeclined) =>
        CallLifecycle.declined,
      (CallLifecycle.calling, CallEvent.busy) => CallLifecycle.busy,
      (CallLifecycle.calling, CallEvent.timeout) => CallLifecycle.ended,
      (CallLifecycle.calling, CallEvent.fail) => CallLifecycle.failed,
      (CallLifecycle.calling, CallEvent.end) => CallLifecycle.ended,
      (CallLifecycle.ringing, CallEvent.accept) => CallLifecycle.connecting,
      (CallLifecycle.ringing, CallEvent.decline) => CallLifecycle.declined,
      (CallLifecycle.ringing, CallEvent.timeout) => CallLifecycle.ended,
      (CallLifecycle.ringing, CallEvent.end) => CallLifecycle.ended,
      (CallLifecycle.connecting, CallEvent.connected) =>
        CallLifecycle.connected,
      (CallLifecycle.connecting, CallEvent.fail) => CallLifecycle.failed,
      (CallLifecycle.connecting, CallEvent.end) => CallLifecycle.ended,
      (CallLifecycle.connected, CallEvent.connectionLost) =>
        CallLifecycle.reconnecting,
      (CallLifecycle.connected, CallEvent.end) => CallLifecycle.ended,
      (CallLifecycle.reconnecting, CallEvent.reconnected) =>
        CallLifecycle.connected,
      (CallLifecycle.reconnecting, CallEvent.connected) =>
        CallLifecycle.connected,
      (CallLifecycle.reconnecting, CallEvent.fail) => CallLifecycle.failed,
      (CallLifecycle.reconnecting, CallEvent.end) => CallLifecycle.ended,
      (_, CallEvent.end) => CallLifecycle.ended,
      (_, CallEvent.fail) => CallLifecycle.failed,
      _ => current,
    };
  }

  static bool isTerminal(CallLifecycle state) {
    return state == CallLifecycle.ended ||
        state == CallLifecycle.declined ||
        state == CallLifecycle.busy ||
        state == CallLifecycle.failed;
  }
}

abstract final class CallPolicy {
  static const Duration ringTimeout = Duration(seconds: 35);

  static bool canStartCall({
    required bool matchActive,
    required bool blocked,
    required bool isParticipant,
    required bool receiverBusy,
  }) {
    return matchActive && !blocked && isParticipant && !receiverBusy;
  }
}
