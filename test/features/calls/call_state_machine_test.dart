import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/calls/domain/call_state_machine.dart';
import 'package:mevora/features/calls/domain/models/call_session.dart';

void main() {
  test('outgoing call lifecycle', () {
    var state = CallLifecycle.idle;
    state = CallStateMachine.transition(state, CallEvent.startOutgoing);
    expect(state, CallLifecycle.calling);
    state = CallStateMachine.transition(state, CallEvent.remoteAccepted);
    expect(state, CallLifecycle.connecting);
    state = CallStateMachine.transition(state, CallEvent.connected);
    expect(state, CallLifecycle.connected);
    state = CallStateMachine.transition(state, CallEvent.connectionLost);
    expect(state, CallLifecycle.reconnecting);
    state = CallStateMachine.transition(state, CallEvent.reconnected);
    expect(state, CallLifecycle.connected);
    state = CallStateMachine.transition(state, CallEvent.end);
    expect(state, CallLifecycle.ended);
  });

  test('incoming decline and busy', () {
    expect(
      CallStateMachine.transition(CallLifecycle.idle, CallEvent.receiveIncoming),
      CallLifecycle.ringing,
    );
    expect(
      CallStateMachine.transition(CallLifecycle.ringing, CallEvent.decline),
      CallLifecycle.declined,
    );
    expect(
      CallStateMachine.transition(CallLifecycle.calling, CallEvent.busy),
      CallLifecycle.busy,
    );
  });

  test('illegal transitions stay put', () {
    expect(
      CallStateMachine.transition(CallLifecycle.idle, CallEvent.connected),
      CallLifecycle.idle,
    );
  });

  test('call authz requires active match and no block', () {
    expect(
      CallPolicy.canStartCall(
        matchActive: true,
        blocked: false,
        isParticipant: true,
        receiverBusy: false,
      ),
      isTrue,
    );
    expect(
      CallPolicy.canStartCall(
        matchActive: false,
        blocked: false,
        isParticipant: true,
        receiverBusy: false,
      ),
      isFalse,
    );
    expect(
      CallPolicy.canStartCall(
        matchActive: true,
        blocked: true,
        isParticipant: true,
        receiverBusy: false,
      ),
      isFalse,
    );
  });
}
