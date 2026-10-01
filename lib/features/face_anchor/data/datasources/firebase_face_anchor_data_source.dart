import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';

/// The Firebase boundary for Face Anchor: the document, the callables and the
/// one Storage path. Above this class the app sees only the domain types.
class FirebaseFaceAnchorDataSource {
  FirebaseFaceAnchorDataSource({
    required BackendCallable backend,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _backend = backend,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final BackendCallable _backend;
  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;

  static const requirementsCallable = 'getFaceAnchorRequirements';
  static const startCallable = 'startFaceAnchorVerification';
  static const submitCallable = 'submitFaceAnchorVerification';

  static const Duration _uploadTimeout = Duration(seconds: 45);

  static String statePath(String uid) => 'users/$uid/faceAnchor/state';

  /// Owner-readable, never client-writable. The server writes every field.
  Stream<FaceAnchorState> watchState(String uid) {
    return _firestore
        .doc(statePath(uid))
        .snapshots()
        .map((snap) => FaceAnchorState.fromMap(snap.data()));
  }

  Future<FaceAnchorRequirements> loadRequirements() async {
    final data = await _backend.invoke(requirementsCallable);
    return FaceAnchorRequirements(
      required: data['required'] == true,
      available: data['available'] == true,
      consentVersion: firestoreInt(data['consentVersion'], 0),
    );
  }

  /// The request carries the photo and the consent the member gave — nothing
  /// else. There is no field that selects how the check is performed.
  Future<FaceAnchorAttempt> startAttempt({
    required String photoId,
    required int consentVersion,
  }) async {
    final data = await _backend.invoke(startCallable, {
      'photoId': photoId,
      'consentVersion': consentVersion,
    });
    final attemptId = data['attemptId'] as String?;
    final uploadPath = data['uploadPath'] as String?;
    if (attemptId == null ||
        attemptId.isEmpty ||
        uploadPath == null ||
        uploadPath.isEmpty) {
      throw const FormatException('Verification attempt could not be opened');
    }
    return FaceAnchorAttempt(
      attemptId: attemptId,
      uploadPath: uploadPath,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        firestoreInt(data['expiresAtMs'], 0),
      ),
    );
  }

  /// Uploads to the path the server named. No download URL is requested: the
  /// rules allow nobody to read this object, the member included.
  Future<void> uploadSelfie({
    required String path,
    required List<int> bytes,
    required String contentType,
  }) async {
    final task = _storage
        .ref(path)
        .putData(
          Uint8List.fromList(bytes),
          SettableMetadata(contentType: contentType),
        );
    try {
      await task.timeout(_uploadTimeout);
    } on TimeoutException {
      try {
        await task.cancel();
      } on Object {
        // Already finished or already cancelled.
      }
      rethrow;
    }
  }

  Future<FaceAnchorState> submitAttempt(String attemptId) async {
    final data = await _backend.invoke(submitCallable, {
      'attemptId': attemptId,
    });
    return FaceAnchorState.fromMap({...data, 'attemptId': attemptId});
  }
}
