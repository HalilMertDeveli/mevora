import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/core/services/app_logger.dart';

/// Best-effort wipe of the local Firestore cache after logout / deletion.
/// `clearPersistence` only succeeds when no listeners are active.
class FirestoreSessionCache {
  const FirestoreSessionCache({this.logger});

  final AppLogger? logger;

  Future<void> clearSensitiveCache() async {
    try {
      await FirebaseFirestore.instance.clearPersistence();
    } on Object catch (error, stackTrace) {
      logger?.warning(
        'Could not clear Firestore persistence on logout',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
