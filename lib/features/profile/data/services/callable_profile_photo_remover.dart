import 'package:cloud_functions/cloud_functions.dart'
    show FirebaseFunctionsException;
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/profile/domain/repositories/profile_photo_remover.dart';

/// [ProfilePhotoRemover] over the `deleteProfilePhoto` callable.
class CallableProfilePhotoRemover implements ProfilePhotoRemover {
  CallableProfilePhotoRemover({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  static const callable = 'deleteProfilePhoto';

  @override
  Future<Result<void>> remove(String photoId) async {
    try {
      await _backend.invoke(callable, {'photoId': photoId});
      return const Success(null);
    } on FirebaseFunctionsException catch (error) {
      return Err(_failureFor(error));
    } on Object catch (error) {
      return Err(NetworkFailure(error.toString()));
    }
  }

  static Failure _failureFor(FirebaseFunctionsException error) {
    switch (error.code) {
      case 'failed-precondition':
        // The message is the server's reason, already a PhotoPolicy key.
        return ValidationFailure(error.message ?? '');
      case 'not-found':
      case 'unimplemented':
        // The callable itself is missing: it never answers this for a photo.
        return NotFoundFailure(error.code);
      default:
        return NetworkFailure(error.message ?? error.code);
    }
  }
}
