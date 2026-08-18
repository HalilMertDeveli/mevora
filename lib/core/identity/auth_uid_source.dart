/// Resolves the signed-in Firebase UID. Identity is never email, phone, or
/// provider id — Google/Apple/Spotify/Phone all share this same UID.
abstract class AuthUidSource {
  String? get currentUid;

  Stream<String?> watchUid();
}
