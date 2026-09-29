import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_step_scaffold.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_lifestyle_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/pump_app.dart';

final _en = lookupAppLocalizations(const Locale('en'));

/// The lifestyle step on a phone-sized screen (the size of the manual test
/// that found it: four chip groups did not fit above Continue).
Future<void> _pumpLifestyleStep(
  WidgetTester tester, {
  Size size = const Size(347, 675),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    wrapWithApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: OnboardingStepScaffold(
              step: OnboardingStep.lifestyle,
              title: _en.onboardingLifestyle,
              subtitle: _en.onboardingWhyLifestyle,
              onBack: () {},
              onContinue: () {},
              scrollable: true,
              child: ProfileLifestylePicker(
                profile: const ProfileLifestyle(),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the lifestyle step scrolls instead of overflowing', (
    tester,
  ) async {
    await _pumpLifestyleStep(tester);

    // A RenderFlex overflow is reported as an exception in tests.
    expect(tester.takeException(), isNull);
    expect(find.text(_en.onboardingContinue), findsOneWidget);

    // The last group is reachable by scrolling, and Continue stays put.
    final continueTop = tester.getTopLeft(find.text(_en.onboardingContinue));
    await tester.scrollUntilVisible(
      find.text(_en.onboardingPets),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(_en.onboardingPets).hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.text(_en.onboardingContinue)), continueTop);
  });

  testWidgets('it still fits at a large text scale', (tester) async {
    await _pumpLifestyleStep(tester, textScale: 1.6);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every lifestyle group starts at the step title edge', (
    tester,
  ) async {
    await _pumpLifestyleStep(tester, size: const Size(390, 1400));

    // Groups line up with the step title, not centred on their own width
    // (which put each group at a different indent).
    final edge = tester.getTopLeft(find.text(_en.onboardingLifestyle)).dx;
    for (final title in [
      _en.onboardingSmoking,
      _en.onboardingDrinking,
      _en.onboardingExercise,
      _en.onboardingPets,
    ]) {
      expect(tester.getTopLeft(find.text(title)).dx, edge, reason: title);
    }
  });
}
