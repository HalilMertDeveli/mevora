import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/location_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/testing/fake_location_repository.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/pump_app.dart';

const _user = AuthUser(id: 'u1');

OnboardingController _controller(FakeOnboardingRepository repository) {
  final services = createFakeOnboardingServices();
  return OnboardingController(
    repository: repository,
    storage: services.storageRepository,
    photoPicker: services.photoPicker,
  );
}

void main() {
  group('the city chosen at the location step', () {
    test('fills a draft that has no city yet', () async {
      final controller = _controller(FakeOnboardingRepository());
      addTearDown(controller.dispose);

      await controller.initialize(_user, cityHint: ' İzmir ');

      expect(controller.profile!.city, 'İzmir');
    });

    test('never replaces a city the draft already has', () async {
      final repository = FakeOnboardingRepository()
        ..saved = const UserProfile(
          uid: 'u1',
          displayName: 'Deniz',
          city: 'Ankara',
        );
      final controller = _controller(repository);
      addTearDown(controller.dispose);

      await controller.initialize(_user, cityHint: 'İzmir');

      expect(controller.profile!.city, 'Ankara');
    });

    test('without one, the draft stays without a city', () async {
      for (final hint in [null, '', '   ']) {
        final controller = _controller(FakeOnboardingRepository());
        addTearDown(controller.dispose);

        await controller.initialize(_user, cityHint: hint);

        expect(controller.profile!.city, isNull, reason: 'hint: "$hint"');
      }
    });
  });

  testWidgets(
    'the onboarding page shows the city picked at the location step',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final services = createFakeOnboardingServices();
      final location = LocationController(
        repository: FakeLocationRepository(),
        successHold: Duration.zero,
      );
      addTearDown(location.dispose);
      await location.syncForUser(_user.id);
      await location.continueWithCity('İzmir');

      final auth = AuthController(
        authRepository: FakeAuthRepository(user: _user),
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..user = _user;
      await tester.pumpWidget(
        wrapWithApp(
          LocationScope(
            repository: location.repository,
            controller: location,
            child: AuthScope(
              controller: auth,
              child: OnboardingScope(
                repository: services.onboardingRepository,
                storage: services.storageRepository,
                photoPicker: services.photoPicker,
                controller: services.controller,
                child: const OnboardingPage(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(services.controller.profile!.city, 'İzmir');
      final fields = tester
          .widgetList<MevoraTextField>(find.byType(MevoraTextField))
          .map((field) => field.controller?.text);
      expect(fields, contains('İzmir'));
    },
  );
}
