import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/profile/domain/repositories/profile_photo_remover.dart';

/// Records what the app asked the server to delete, and answers as told.
class FakeProfilePhotoRemover implements ProfilePhotoRemover {
  FakeProfilePhotoRemover({this.failure});

  /// What every call answers; null means the server deleted the photo.
  Failure? failure;

  final List<String> removed = <String>[];

  @override
  Future<Result<void>> remove(String photoId) async {
    removed.add(photoId);
    final failure = this.failure;
    return failure == null ? const Success(null) : Err(failure);
  }
}
