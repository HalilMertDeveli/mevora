import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';

/// Streams `appOperationsConfig/public`. The server is its only writer; the
/// app never writes to it.
class FirestoreAppOperationsRepository implements AppOperationsRepository {
  FirestoreAppOperationsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore;

  static const String collection = 'appOperationsConfig';
  static const String documentId = 'public';

  final FirebaseFirestore? _firestore;

  @override
  Stream<AppOperationsConfig> watch() {
    final firestore = _firestore ?? FirebaseFirestore.instance;
    return firestore
        .collection(collection)
        .doc(documentId)
        .snapshots()
        .map(
          (snapshot) => snapshot.exists
              ? AppOperationsConfig.fromMap(
                  normalizeFirestoreValue(snapshot.data()),
                )
              : AppOperationsConfig.defaults,
        );
  }
}

/// Replaces every [Timestamp] with a [DateTime] so the domain model never
/// depends on Firestore types.
Object? normalizeFirestoreValue(Object? value) {
  return switch (value) {
    final Timestamp timestamp => timestamp.toDate(),
    final Map<Object?, Object?> map => {
      for (final entry in map.entries)
        entry.key.toString(): normalizeFirestoreValue(entry.value),
    },
    final List<Object?> list => [
      for (final item in list) normalizeFirestoreValue(item),
    ],
    _ => value,
  };
}
