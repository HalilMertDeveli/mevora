import 'package:mevora/features/profile/domain/entities/user_profile.dart';

/// The rules for a member's own photo list: 3 minimum, 6 maximum, and — once
/// the profile has a verified Face Anchor — a primary photo that is always
/// one.
///
/// Onboarding and the edit page both go through this class, so a rule holds
/// in both. It is a convenience for the member, not the authority: the server
/// imposes the same rules on whatever is written (`photoInvariants.ts`), so a
/// client that skipped these checks would simply have its write corrected.
abstract final class PhotoPolicy {
  static const int minPhotos = 3;
  static const int maxPhotos = 6;

  /// Reasons a change is refused. `SettingsStrings.validation` and
  /// `OnboardingErrorL10n` turn them into the member's language.
  static const String minRequired = 'photo_min_required';
  static const String primaryDeleteBlocked = 'photo_primary_delete_blocked';
  static const String lastFaceAnchor = 'photo_last_face_anchor';
  static const String primaryRequiresFaceAnchor =
      'photo_primary_requires_face_anchor';
  static const String notFound = 'photo_not_found';

  static bool canAdd(int currentCount) => currentCount < maxPhotos;

  static bool hasFaceAnchor(List<ProfilePhoto> photos) =>
      photos.any((photo) => photo.isFaceAnchor);

  static bool canDelete(List<ProfilePhoto> photos, String photoId) {
    return photos.any((photo) => photo.id == photoId) &&
        deleteBlockReason(photos, photoId) == null;
  }

  static String? deleteBlockReason(List<ProfilePhoto> photos, String photoId) {
    if (photos.length <= minPhotos) {
      return minRequired;
    }
    final target = photos.where((p) => p.id == photoId).firstOrNull;
    if (target == null) {
      return null;
    }
    if (target.isFaceAnchor) {
      // A verified photo may go as long as another one stays. If it was the
      // primary, the remaining anchor takes its place (see [normalize]).
      final others = photos.where((p) => p.id != photoId && p.isFaceAnchor);
      return others.isEmpty ? lastFaceAnchor : null;
    }
    if (target.isPrimary) {
      return primaryDeleteBlocked;
    }
    return null;
  }

  /// Why [photoId] cannot be made the primary photo, or null if it can.
  static String? setPrimaryBlockReason(
    List<ProfilePhoto> photos,
    String photoId,
  ) {
    final target = photos.where((p) => p.id == photoId).firstOrNull;
    if (target == null) {
      return notFound;
    }
    return target.isFaceAnchor ? null : primaryRequiresFaceAnchor;
  }

  /// Why the photo at [oldIndex] cannot be moved to [newIndex], or null.
  ///
  /// Indices are positions in display order, [newIndex] already adjusted for
  /// the removal. With a Face Anchor on the profile the first position is the
  /// primary photo, so only an anchor may be moved into it — or left in it
  /// when the current primary is moved away.
  static String? reorderBlockReason(
    List<ProfilePhoto> photos,
    int oldIndex,
    int newIndex,
  ) {
    final sorted = _sorted(photos);
    if (!_inRange(sorted, oldIndex, newIndex) || oldIndex == newIndex) {
      return null;
    }
    if (!hasFaceAnchor(sorted)) {
      return null;
    }
    final moved = [...sorted];
    final item = moved.removeAt(oldIndex);
    moved.insert(newIndex, item);
    return moved.first.isFaceAnchor ? null : primaryRequiresFaceAnchor;
  }

  /// Moves a photo. With a Face Anchor on the profile, whichever anchor ends
  /// up first becomes the primary photo; a move that would put anything else
  /// first is ignored (see [reorderBlockReason]).
  static List<ProfilePhoto> reorder(
    List<ProfilePhoto> photos,
    int oldIndex,
    int newIndex,
  ) {
    final sorted = _sorted(photos);
    if (!_inRange(sorted, oldIndex, newIndex) ||
        reorderBlockReason(sorted, oldIndex, newIndex) != null) {
      return normalize(sorted);
    }
    final item = sorted.removeAt(oldIndex);
    sorted.insert(newIndex, item);
    final anchored = hasFaceAnchor(sorted);
    return [
      for (var i = 0; i < sorted.length; i++)
        sorted[i].copyWith(
          order: i,
          isPrimary: anchored ? i == 0 : sorted[i].isPrimary,
        ),
    ];
  }

  /// Makes [photoId] the primary photo and moves it first. Unchanged when the
  /// photo is not a verified Face Anchor (see [setPrimaryBlockReason]).
  static List<ProfilePhoto> setPrimary(
    List<ProfilePhoto> photos,
    String photoId,
  ) {
    if (setPrimaryBlockReason(photos, photoId) != null) {
      return normalize(photos);
    }
    final sorted = _sorted(photos);
    final target = sorted.firstWhere((p) => p.id == photoId);
    final rest = sorted.where((p) => p.id != photoId);
    final ordered = [target, ...rest];
    return [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(order: i, isPrimary: i == 0),
    ];
  }

  /// Display order with gaps closed and exactly one primary photo.
  ///
  /// With a Face Anchor on the profile, the primary is an anchor and sits
  /// first: the one already marked primary, otherwise the first anchor. A
  /// profile with no anchor keeps its own choice, as it always did.
  static List<ProfilePhoto> normalize(List<ProfilePhoto> photos) {
    final sorted = _sorted(photos);
    final anchors = sorted.where((p) => p.isFaceAnchor).toList();
    if (anchors.isEmpty) {
      final hasPrimary = sorted.any((p) => p.isPrimary);
      return [
        for (var i = 0; i < sorted.length; i++)
          sorted[i].copyWith(
            order: i,
            isPrimary: hasPrimary ? sorted[i].isPrimary : i == 0,
          ),
      ];
    }
    final primary =
        anchors.where((p) => p.isPrimary).firstOrNull ?? anchors.first;
    final ordered = [primary, ...sorted.where((p) => !identical(p, primary))];
    return [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(order: i, isPrimary: i == 0),
    ];
  }

  static List<ProfilePhoto> _sorted(List<ProfilePhoto> photos) {
    // Stable for equal orders: a photo keeps its position among its peers.
    final indexed = [
      for (var i = 0; i < photos.length; i++) (index: i, photo: photos[i]),
    ];
    indexed.sort((a, b) {
      final byOrder = a.photo.order.compareTo(b.photo.order);
      return byOrder != 0 ? byOrder : a.index.compareTo(b.index);
    });
    return [for (final entry in indexed) entry.photo];
  }

  static bool _inRange(List<ProfilePhoto> photos, int oldIndex, int newIndex) {
    return oldIndex >= 0 &&
        newIndex >= 0 &&
        oldIndex < photos.length &&
        newIndex < photos.length;
  }
}
