import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:mevora/core/errors/app_exception.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/storage/storage_provider.dart';

class FirebaseStorageAdapter implements StorageProvider {
  FirebaseStorageAdapter({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  @override
  Future<Result<Uri>> uploadBytes({
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
    void Function(double progress)? onProgress,
  }) async {
    try {
      final ref = _storage.ref(path);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(contentType: contentType),
      );
      final url = await ref.getDownloadURL();
      return Success(Uri.parse(url));
    } on Object catch (error) {
      return Err(
        FailureMapper.from(
          NetworkException('Could not upload that file.', cause: error),
        ),
      );
    }
  }

  @override
  Future<Result<void>> delete(String path) async {
    try {
      await _storage.ref(path).delete();
      return const Success(null);
    } on Object catch (error) {
      return Err(
        FailureMapper.from(
          NetworkException('Could not delete that file.', cause: error),
        ),
      );
    }
  }
}
