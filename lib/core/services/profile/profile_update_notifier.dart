import 'package:flutter/foundation.dart';

/// Notifies listeners when the signed-in user's profile or preferences change.
class ProfileUpdateNotifier extends ChangeNotifier {
  String? _lastUpdatedUid;

  String? get lastUpdatedUid => _lastUpdatedUid;

  void notifyProfileUpdated(String uid) {
    _lastUpdatedUid = uid;
    notifyListeners();
  }
}
