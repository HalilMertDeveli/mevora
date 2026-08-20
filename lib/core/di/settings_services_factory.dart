import 'package:mevora/features/onboarding/data/services/image_picker_profile_photo_picker.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/data/datasources/firebase_storage_data_source.dart';
import 'package:mevora/features/profile/data/repositories/storage_repository_impl.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';
import 'package:mevora/features/settings/data/repositories/settings_hub_repository_impl.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/repositories/settings_hub_repository.dart';

class SettingsServices {
  const SettingsServices({
    required this.settingsHub,
    required this.photoManager,
    required this.reauthService,
    required this.photoPicker,
  });

  final SettingsHubRepository settingsHub;
  final ProfilePhotoManager photoManager;
  final ReauthPort reauthService;
  final ProfilePhotoPicker photoPicker;
}

SettingsServices createSettingsServices({
  required ReauthPort reauthService,
  ProfilePhotoPicker? photoPicker,
}) {
  final profileDataSource = FirebaseProfileDataSource();
  final settingsDataSource = FirebaseSettingsDataSource();
  final settingsHub = SettingsHubRepositoryImpl(
    profileDataSource: profileDataSource,
    settingsDataSource: settingsDataSource,
  );
  final storage = StorageRepositoryImpl(
    dataSource: FirebaseStorageDataSource(),
  );
  return SettingsServices(
    settingsHub: settingsHub,
    photoManager: ProfilePhotoManager(
      settingsHub: settingsHub,
      storage: storage,
    ),
    reauthService: reauthService,
    photoPicker: photoPicker ?? ImagePickerProfilePhotoPicker(),
  );
}
