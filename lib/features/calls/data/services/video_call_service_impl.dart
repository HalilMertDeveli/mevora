import 'package:mevora/features/calls/domain/models/call_session.dart';
import 'package:mevora/features/calls/domain/services/video_call_provider.dart';

class VideoCallServiceImpl implements VideoCallService {
  VideoCallServiceImpl(this._repository);

  final CallRepository _repository;

  @override
  Future<CallSession> startCall({
    required String matchId,
    required String receiverId,
  }) {
    return _repository.createCall(matchId: matchId, receiverId: receiverId);
  }

  @override
  Future<CallSession> acceptCall(String callId) {
    return _repository.respond(callId: callId, accept: true);
  }

  @override
  Future<void> declineCall(String callId) {
    return _repository.respond(callId: callId, accept: false);
  }

  @override
  Future<void> endCall(String callId) => _repository.end(callId);

  @override
  Future<void> expireCall(String callId) => _repository.expire(callId);

  @override
  Stream<CallSession> watchIncoming(String uid) {
    return _repository.watchIncoming(uid).expand((calls) => calls);
  }

  @override
  Stream<CallSession?> watchCall(String callId) {
    return _repository.watchCall(callId);
  }
}
