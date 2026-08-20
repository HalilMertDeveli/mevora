import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  testWidgets('education step renders options', (tester) async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final controller = services.controller;
    await controller.initialize(const AuthUser(id: 'u1'));
    controller.step = OnboardingStep.education;

    await tester.pumpWidget(
      wrapWithApp(
        AuthScope(
          controller: AuthController(
            authRepository: FakeAuthRepository(
              user: const AuthUser(id: 'u1'),
            ),
            userDocumentRepository: FakeUserDocumentRepository(),
            logger: const AppLogger(environment: AppEnvironment.development),
          ),
          child: OnboardingScope(
            repository: services.onboardingRepository,
            storage: services.storageRepository,
            photoPicker: services.photoPicker,
            controller: controller,
            child: const OnboardingPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(l10n.onboardingEducationBachelors), findsOneWidget);
    await tester.tap(find.text(l10n.onboardingEducationMasters));
    await tester.pumpAndSettle();
    expect(controller.profile!.education, OnboardingEducation.masters);
  });
}
