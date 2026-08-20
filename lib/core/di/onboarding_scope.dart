import 'package:flutter/widgets.dart';
import 'package:mevora/features/onboarding/domain/repositories/onboarding_repository.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/profile/domain/repositories/storage_repository.dart';

class OnboardingScope extends InheritedWidget {
  const OnboardingScope({
    super.key,
    required this.repository,
    required this.storage,
    required this.photoPicker,
    required this.controller,
    required super.child,
  });

  final OnboardingRepository repository;
  final StorageRepository storage;
  final ProfilePhotoPicker photoPicker;
  final OnboardingController controller;

  static OnboardingScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OnboardingScope>();
    assert(scope != null, 'OnboardingScope not found in the widget tree');
    return scope!;
  }

  static OnboardingScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<OnboardingScope>();
  }

  @override
  bool updateShouldNotify(OnboardingScope oldWidget) {
    return repository != oldWidget.repository ||
        storage != oldWidget.storage ||
        photoPicker != oldWidget.photoPicker ||
        controller != oldWidget.controller;
  }
}
