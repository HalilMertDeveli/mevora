import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// Profile photo limits: 3 minimum, 6 maximum. Primary photo is required.
abstract final class PhotoPolicy {
  static const int minPhotos = 3;
  static const int maxPhotos = 6;

  static bool canAdd(int currentCount) => currentCount < maxPhotos;

  static bool canDelete(List<ProfilePhoto> photos, String photoId) {
    if (photos.length <= minPhotos) {
      return false;
    }
    final target = photos.where((p) => p.id == photoId).firstOrNull;
    if (target == null) {
      return false;
    }
    if (target.isPrimary && photos.length > minPhotos) {
      return false;
    }
    return true;
  }

  static String? deleteBlockReason(List<ProfilePhoto> photos, String photoId) {
    if (photos.length <= minPhotos) {
      return 'photo_min_required';
    }
    final target = photos.where((p) => p.id == photoId).firstOrNull;
    if (target?.isPrimary == true) {
      return 'photo_primary_delete_blocked';
    }
    return null;
  }

  static List<ProfilePhoto> reorder(List<ProfilePhoto> photos, int oldIndex, int newIndex) {
    final sorted = [...photos]..sort((a, b) => a.order.compareTo(b.order));
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= sorted.length ||
        newIndex >= sorted.length) {
      return sorted;
    }
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);
    return [
      for (var i = 0; i < sorted.length; i++) sorted[i].copyWith(order: i),
    ];
  }

  static List<ProfilePhoto> setPrimary(List<ProfilePhoto> photos, String photoId) {
    return [
      for (final photo in photos)
        photo.copyWith(isPrimary: photo.id == photoId),
    ];
  }

  static List<ProfilePhoto> normalize(List<ProfilePhoto> photos) {
    final sorted = [...photos]..sort((a, b) => a.order.compareTo(b.order));
    var hasPrimary = sorted.any((p) => p.isPrimary);
    return [
      for (var i = 0; i < sorted.length; i++)
        sorted[i].copyWith(
          order: i,
          isPrimary: hasPrimary ? sorted[i].isPrimary : i == 0,
        ),
    ];
  }
}
