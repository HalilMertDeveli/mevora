import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mevora/features/onboarding/data/repositories/onboarding_repository_impl.dart';
import 'package:mevora/features/onboarding/data/services/image_picker_profile_photo_picker.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/data/datasources/firebase_profile_data_source.dart';
import 'package:mevora/features/profile/data/datasources/firebase_storage_data_source.dart';
import 'package:mevora/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:mevora/features/profile/data/repositories/storage_repository_impl.dart';
import 'package:mevora/features/profile/domain/repositories/profile_repository.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class OnboardingServices {
  const OnboardingServices({
    required this.profileRepository,
    required this.storageRepository,
    required this.onboardingRepository,
    required this.photoPicker,
    required this.controller,
  });

  final ProfileRepository profileRepository;
  final StorageRepository storageRepository;
  final OnboardingRepository onboardingRepository;
  final ProfilePhotoPicker photoPicker;
  final OnboardingController controller;
}

OnboardingServices createOnboardingServices({
  ProfileRepository? profiles,
  StorageRepository? storage,
  OnboardingRepository? onboarding,
  ProfilePhotoPicker? photoPicker,
  FirebaseFirestore? firestore,
}) {
  final profileRepository =
      profiles ??
      ProfileRepositoryImpl(
        dataSource: FirebaseProfileDataSource(firestore: firestore),
      );
  final storageRepository =
      storage ?? StorageRepositoryImpl(dataSource: FirebaseStorageDataSource());
  final onboardingRepository =
      onboarding ??
      OnboardingRepositoryImpl(
        profiles: profileRepository,
        firestore: firestore,
      );
  final picker = photoPicker ?? ImagePickerProfilePhotoPicker();
  final controller = OnboardingController(
    repository: onboardingRepository,
    storage: storageRepository,
    photoPicker: picker,
  );
  return OnboardingServices(
    profileRepository: profileRepository,
    storageRepository: storageRepository,
    onboardingRepository: onboardingRepository,
    photoPicker: picker,
    controller: controller,
  );
}
