import 'package:mevora/features/authentication/domain/entities/auth_user.dart';

abstract class UserDocumentRepository {
  Future<void> ensureUserDocument(AuthUser user);

  Future<bool> isProfileComplete(String userId);
}
