import 'package:mevora/features/chat/data/datasources/firebase_chat_data_source.dart';
import 'package:mevora/features/chat/domain/models/chat_message.dart';
import 'package:mevora/features/chat/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl({required FirebaseChatDataSource dataSource})
    : _dataSource = dataSource;

  final FirebaseChatDataSource _dataSource;

  @override
  Stream<List<ChatMessage>> watchLatest(String matchId, {int limit = 30}) {
    return _dataSource.watchLatest(matchId, limit: limit);
  }

  @override
  Future<ChatPage> loadOlder({
    required String matchId,
    required ChatMessage before,
    int limit = 30,
  }) {
    return _dataSource.loadOlder(
      matchId: matchId,
      before: before,
      limit: limit,
    );
  }

  @override
  Future<ChatMessage> sendText({
    required String matchId,
    required String receiverId,
    required String text,
  }) {
    return _dataSource.sendText(
      matchId: matchId,
      receiverId: receiverId,
      text: text,
    );
  }

  @override
  Future<void> markDelivered(String matchId, List<ChatMessage> messages) {
    return _dataSource.markDelivered(matchId, messages);
  }

  @override
  Future<void> markRead(String matchId, List<ChatMessage> messages) {
    return _dataSource.markRead(matchId, messages);
  }

  @override
  Future<void> setTyping({required String matchId, required bool isTyping}) {
    return _dataSource.setTyping(matchId: matchId, isTyping: isTyping);
  }

  @override
  Stream<Map<String, DateTime>> watchTyping(String matchId) {
    return _dataSource.watchTyping(matchId);
  }
}
