import 'package:mevora/core/errors/result.dart';

/// Deletes one of the signed-in member's profile photos for good: the entry
/// on the profile, the stored image and its display variants.
///
/// Only the server can do this. The published copy of a photo is not
/// writable by clients, so a client that merely drops the photo from its
/// profile leaves the image itself in storage.
///
/// A refusal carries the reason as a [ValidationFailure] message, in the
/// vocabulary of `PhotoPolicy` (`photo_min_required`, …). A
/// [NotFoundFailure] means this backend has no such operation yet.
abstract class ProfilePhotoRemover {
  Future<Result<void>> remove(String photoId);
}
