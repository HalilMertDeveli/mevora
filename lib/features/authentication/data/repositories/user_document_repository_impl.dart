import 'package:mevora/features/authentication/data/datasources/user_remote_datasource.dart';
import 'package:mevora/features/authentication/domain/entities/auth_session.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';

class UserDocumentRepositoryImpl implements UserDocumentRepository {
  UserDocumentRepositoryImpl(this._remote);

  final UserRemoteDataSource _remote;

  @override
  Future<void> ensureUserDocument(AuthUser user) async {
    await _remote.upsertFromSession(
      AuthSession(
        uid: user.id,
        provider: null,
        email: user.email,
        displayName: user.displayName,
        photoUrl: user.photoUrl,
        persistEmail: user.email != null,
      ),
    );
  }

  @override
  Future<bool> isProfileComplete(String userId) async {
    final document = await _remote.findUser(userId);
    if (document == null) {
      return false;
    }
    return document.isProfileComplete;
  }
}
