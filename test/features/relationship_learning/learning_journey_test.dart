import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/humor_scope.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/humor/data/datasources/mock_humor_data_source.dart';
import 'package:mevora/features/humor/data/repositories/humor_repository_impl.dart';
import 'package:mevora/features/humor/presentation/pages/humor_calibration_intro_page.dart';
import 'package:mevora/features/relationship_learning/domain/entities/relationship_learning.dart';
import 'package:mevora/features/relationship_learning/presentation/controllers/learning_journey_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';

import 'learning_fakes.dart';

class _RecordingAnalytics implements AnalyticsProvider {
  final List<String> events = [];

  @override
  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    events.add(name);
  }

  @override
  Future<void> setUserId(String? userId) async {}
}

void main() {
  const member = AuthUser(id: 'new', onboardingCompleted: true);
  const humorRoute = AppRoutes.humorCalibration;
  const learningRoute = LearningJourneyController.learningRoute;

  String? redirect(
    String location, {
    String? journeyRoute,
    bool pending = false,
    AuthStatus status = const Authenticated(member),
  }) {
    return AuthRedirector.redirect(
      status: status,
      location: location,
      journeyRoute: journeyRoute,
      journeyPending: pending,
    );
  }

  group('first-run routing', () {
    test(
      'new account: profile first, then humor, then questions, then app',
      () {
        // 1. Basic profile incomplete: onboarding, whatever the journey says.
        expect(
          redirect(
            AppRoutes.discovery,
            journeyRoute: humorRoute,
            status: const Authenticated(AuthUser(id: 'new')),
          ),
          AppRoutes.onboarding,
        );
        // 2. Profile done, humor owed.
        expect(
          redirect(AppRoutes.onboarding, journeyRoute: humorRoute),
          humorRoute,
        );
        expect(
          redirect(AppRoutes.discovery, journeyRoute: humorRoute),
          humorRoute,
        );
        // 3. Humor done, questions owed.
        expect(
          redirect(AppRoutes.discovery, journeyRoute: learningRoute),
          learningRoute,
        );
        expect(
          redirect(AppRoutes.matches, journeyRoute: learningRoute),
          learningRoute,
        );
        // 4. Done: the normal app.
        expect(redirect(AppRoutes.onboarding), AppRoutes.discovery);
        expect(redirect(AppRoutes.discovery), isNull);
      },
    );

    test('each step, and the ways out of it, stay reachable (no loops)', () {
      for (final route in [humorRoute, learningRoute]) {
        for (final allowed in [
          AppRoutes.humorCalibration,
          AppRoutes.humorLab,
          AppRoutes.humorResult,
          AppRoutes.relationshipLearning,
          AppRoutes.settings,
          AppRoutes.accountSettings,
          AppRoutes.legalPrivacy,
        ]) {
          expect(
            redirect(allowed, journeyRoute: route),
            isNull,
            reason: '$allowed during $route',
          );
        }
      }
    });

    test('a restart lands on the owed step, not on Discover', () {
      expect(redirect(AppRoutes.splash, journeyRoute: humorRoute), humorRoute);
      expect(
        redirect(AppRoutes.splash, journeyRoute: learningRoute),
        learningRoute,
      );
    });

    test('while the journey is first read, entry holds on the splash', () {
      expect(redirect(AppRoutes.splash, pending: true), isNull);
      expect(redirect(AppRoutes.onboarding, pending: true), AppRoutes.splash);
      // Deep links are not held hostage by a slow read.
      expect(redirect(AppRoutes.matches, pending: true), isNull);
    });

    test('existing members are never routed by the journey', () {
      expect(redirect(AppRoutes.discovery), isNull);
      expect(redirect(AppRoutes.profile), isNull);
      expect(redirect(AppRoutes.login), AppRoutes.discovery);
    });
  });

  group('journey controller', () {
    LearningJourneyController controllerFor(
      FakeRelationshipLearningRepository repository, {
      bool humorEnabled = true,
      AnalyticsProvider? analytics,
    }) {
      final controller = LearningJourneyController(
        repository: repository,
        humorEnabled: humorEnabled,
        analytics: analytics,
      );
      addTearDown(controller.dispose);
      return controller;
    }

    test('maps the server stage to the owed route', () async {
      final repository = FakeRelationshipLearningRepository(required: true)
        ..journeyStage = JourneyStage.humor;
      final journey = controllerFor(repository);
      journey.startFor('new');
      expect(journey.pending, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(journey.pending, isFalse);
      expect(journey.requiredRoute, AppRoutes.humorCalibration);

      repository.journeyStage = JourneyStage.learning;
      await journey.refresh();
      expect(journey.requiredRoute, LearningJourneyController.learningRoute);

      repository.journeyStage = JourneyStage.done;
      await journey.refresh();
      expect(journey.requiredRoute, isNull);
    });

    test('with the Humor Lab off, humor is not a step', () async {
      final repository = FakeRelationshipLearningRepository(required: true)
        ..journeyStage = JourneyStage.humor;
      final journey = controllerFor(repository, humorEnabled: false);
      await journey.refresh();
      expect(journey.requiredRoute, LearningJourneyController.learningRoute);
    });

    test('a failed read never locks anyone in', () async {
      final repository = FakeRelationshipLearningRepository()..failLoads = true;
      final journey = controllerFor(repository);
      await journey.refresh();
      expect(journey.stage, JourneyStage.done);
      expect(journey.requiredRoute, isNull);
    });

    test(
      'a refresh that confirms the same stage does not wake the router',
      () async {
        final repository = FakeRelationshipLearningRepository(required: true)
          ..journeyStage = JourneyStage.learning;
        final journey = controllerFor(repository);
        await journey.refresh();
        var notifications = 0;
        journey.addListener(() => notifications += 1);
        await journey.refresh();
        await journey.refresh();
        expect(
          notifications,
          0,
          reason: 'pushed pages must not be rebuilt mid-flow',
        );
        repository.journeyStage = JourneyStage.done;
        await journey.refresh();
        expect(notifications, 1);
      },
    );

    test('sign-out forgets the member', () async {
      final repository = FakeRelationshipLearningRepository(required: true)
        ..journeyStage = JourneyStage.learning;
      final journey = controllerFor(repository);
      await journey.refresh();
      journey.clear();
      expect(journey.requiredRoute, isNull);
      expect(journey.pending, isFalse);
    });

    test('logs humor onboarding start and completion once each', () async {
      final analytics = _RecordingAnalytics();
      final repository = FakeRelationshipLearningRepository(required: true)
        ..journeyStage = JourneyStage.humor;
      final journey = controllerFor(repository, analytics: analytics);
      await journey.refresh();
      await journey.refresh();
      repository.journeyStage = JourneyStage.learning;
      await journey.refresh();
      expect(analytics.events, [
        AnalyticsEvents.humorOnboardingStarted,
        AnalyticsEvents.humorOnboardingCompleted,
      ]);
    });
  });

  testWidgets(
    'skipping the Humor Lab during the journey is recorded, then moves on',
    (tester) async {
      final repository = FakeRelationshipLearningRepository(required: true)
        ..journeyStage = JourneyStage.humor;
      final journey = LearningJourneyController(
        repository: repository,
        humorEnabled: true,
      );
      addTearDown(journey.dispose);
      await journey.refresh();
      var exited = false;
      await tester.pumpWidget(
        HumorScope(
          repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
          child: RelationshipLearningScope(
            repository: repository,
            journey: journey,
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('tr'),
              home: HumorCalibrationIntroPage(onExit: () => exited = true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
      await tester.tap(find.text(l10n.humorCalibrationSkip).last);
      await tester.pumpAndSettle();
      expect(repository.humorSkips, 1);
      expect(journey.stage, JourneyStage.learning);
      expect(exited, isTrue);
    },
  );

  testWidgets('outside the journey, a humor skip records nothing', (
    tester,
  ) async {
    final repository = FakeRelationshipLearningRepository();
    final journey = LearningJourneyController(
      repository: repository,
      humorEnabled: true,
    );
    addTearDown(journey.dispose);
    await journey.refresh();
    await tester.pumpWidget(
      HumorScope(
        repository: HumorRepositoryImpl(dataSource: MockHumorDataSource()),
        child: RelationshipLearningScope(
          repository: repository,
          journey: journey,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('tr'),
            home: HumorCalibrationIntroPage(onExit: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('tr'));
    await tester.tap(find.text(l10n.humorCalibrationSkip).last);
    await tester.pumpAndSettle();
    expect(repository.humorSkips, 0);
  });
}
