import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/verification/domain/entities/profile_verification.dart';

abstract class VerificationRepository {
  Stream<ProfileVerification> watchVerification(String uid);

  Future<Result<String>> createAccessToken();
}
