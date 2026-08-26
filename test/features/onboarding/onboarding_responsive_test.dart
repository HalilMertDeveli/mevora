import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_onboarding_services.dart';
import '../../helpers/pump_app.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  Future<void> pumpOnboarding(
    WidgetTester tester, {
    required OnboardingStep step,
    Size size = const Size(360, 640),
    double textScale = 1,
  }) async {
    final services = createFakeOnboardingServices();
    addTearDown(services.controller.dispose);
    final controller = services.controller;
    await controller.initialize(const AuthUser(id: 'u1'));
    controller.step = step;

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
        scaffold: false,
      ),
    );
    // Avoid pumpAndSettle — Rive / progress loops may never idle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('interests step scrolls on small phone and keeps Continue', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      step: OnboardingStep.interests,
      size: const Size(360, 640),
    );

    expect(find.text(l10n.onboardingContinue), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Content should be scrollable when chips exceed viewport.
    final scrollable = find.byType(SingleChildScrollView);
    expect(scrollable, findsWidgets);
    await tester.drag(scrollable.first, const Offset(0, -400));
    await tester.pump();
    expect(find.text(l10n.onboardingContinue), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lifestyle step does not overflow at large text scale', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      step: OnboardingStep.lifestyle,
      size: const Size(360, 640),
      textScale: 1.3,
    );

    expect(find.text(l10n.onboardingContinue), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -300),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('basic info continue stays visible on small phone', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      step: OnboardingStep.basicInfo,
      size: const Size(360, 640),
    );

    final continueBtn = find.text(l10n.onboardingContinue);
    expect(continueBtn, findsOneWidget);
    await tester.ensureVisible(continueBtn);
    expect(tester.takeException(), isNull);
  });

  testWidgets('photos step keeps Continue on large phone', (tester) async {
    await pumpOnboarding(
      tester,
      step: OnboardingStep.photos,
      size: const Size(430, 932),
    );
    expect(find.text(l10n.onboardingContinue), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('complete step keeps Start Discovering on Android-ish size', (
    tester,
  ) async {
    await pumpOnboarding(
      tester,
      step: OnboardingStep.complete,
      size: const Size(412, 915),
    );
    expect(find.text(l10n.onboardingStartDiscovering), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
