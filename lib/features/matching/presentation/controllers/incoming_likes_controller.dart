import 'package:flutter/foundation.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';

class IncomingLikesController extends ChangeNotifier {
  IncomingLikesController({required IncomingLikesRepository repository})
    : _repository = repository;

  final IncomingLikesRepository _repository;

  IncomingLikesSnapshot snapshot = IncomingLikesSnapshot.empty;
  bool loading = false;
  String? error;
  bool _closed = false;

  Future<void> load() async {
    if (_closed) {
      return;
    }
    loading = true;
    error = null;
    notifyListeners();
    try {
      final next = await _repository.fetchIncomingLikes();
      if (_closed) {
        return;
      }
      // Defense in depth: never keep identity payloads when locked.
      snapshot = next.locked || next.premiumRequired
          ? IncomingLikesSnapshot(
              locked: true,
              isPremium: false,
              premiumRequired: true,
              count: next.count,
            )
          : next;
      loading = false;
      notifyListeners();
    } on Object catch (err) {
      if (_closed) {
        return;
      }
      error = err.toString();
      loading = false;
      notifyListeners();
    }
  }

  void clear() {
    snapshot = IncomingLikesSnapshot.empty;
    error = null;
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
