import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/features/verification/data/datasources/firebase_verification_data_source.dart';
import 'package:mevora/features/verification/data/repositories/verification_repository_impl.dart';
import 'package:mevora/features/verification/domain/repositories/verification_repository.dart';

class VerificationServices {
  const VerificationServices({required this.repository});

  final VerificationRepository repository;
}

VerificationServices createVerificationServices({BackendCallable? backend}) {
  final remote = FirebaseVerificationDataSource(
    backend: backend ?? FirebaseFunctionsCallable(),
  );
  return VerificationServices(
    repository: VerificationRepositoryImpl(remote: remote),
  );
}
