import 'package:mevora/features/profile/data/datasources/firebase_storage_data_source.dart';
import 'package:mevora/features/profile/data/repositories/storage_repository_impl.dart';
import 'package:mevora/features/support/data/datasources/firebase_support_data_source.dart';
import 'package:mevora/features/support/data/repositories/support_repository_impl.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';

SupportRepository createSupportRepository() {
  return SupportRepositoryImpl(
    dataSource: FirebaseSupportDataSource(),
    storage: StorageRepositoryImpl(
      dataSource: FirebaseStorageDataSource(),
    ),
  );
}
