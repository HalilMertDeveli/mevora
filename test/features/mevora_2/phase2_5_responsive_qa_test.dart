import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/config/app_environment.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/pages/login_page.dart';
import 'package:mevora/features/authentication/presentation/pages/password_reset_page.dart';
import 'package:mevora/features/authentication/presentation/pages/register_page.dart';
import 'package:mevora/features/authentication/presentation/screens/phone_login_screen.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_action_buttons.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_profile_card.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

import '../../helpers/fake_auth.dart';

typedef _Size = ({double w, double h, String label});

const _devices = <_Size>[
  (w: 360, h: 640, label: '360x640'),
  (w: 360, h: 800, label: '360x800'),
  (w: 390, h: 844, label: '390x844'),
  (w: 412, h: 915, label: '412x915'),
  (w: 430, h: 932, label: '430x932'),
  (w: 375, h: 667, label: '375x667'),
  (w: 393, h: 852, label: '393x852'),
];

const _textScales = [0.8, 1.0, 1.15, 1.3];

final _en = lookupAppLocalizations(const Locale('en'));
final _tr = lookupAppLocalizations(const Locale('tr'));

Future<void> _configureViewport(
  WidgetTester tester,
  _Size size,
  double textScale,
) async {
  tester.view.physicalSize = Size(size.w, size.h);
  tester.view.devicePixelRatio = 1.0;
}

void _resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

Widget _withScale(Widget child, double scale, {Brightness brightness = Brightness.light}) {
  return MaterialApp(
    theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
    darkTheme: AppTheme.dark(),
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(scale),
        padding: const EdgeInsets.only(top: 44, bottom: 34),
      ),
      child: child!,
    ),
    home: child,
  );
}

Widget _authApp(Widget page, AuthController controller) {
  const environment = AppEnvironment.development;
  return AppScope(
    config: const AppConfig(environment: environment),
    logger: const AppLogger(environment: environment),
    child: AuthScope(
      controller: controller,
      child: _withScale(page, 1.0),
    ),
  );
}

DiscoveryCandidate _extremeCandidate({int score = 99}) {
  return DiscoveryCandidate(
    uid: 'extreme',
    displayName: 'Alexandrina Constantinopolitanopolous',
    age: 29,
    city: 'Istanbul Metropolitan Area',
    bio:
        'Coffee enthusiast, long-form bio that should remain readable through '
        'scroll rather than being clipped away on smaller devices without any '
        'way for the user to read the full text content here.',
    compatibilityScore: score,
    compatibilityStatus: CompatibilityDisplayStatus.ready,
    isVerified: true,
    interests: List.generate(12, (i) => 'interest_$i'),
    sharedInterests: List.generate(5, (i) => 'shared_$i'),
    compatibilityReasons: const [
      'Strong alignment on lifestyle and communication preferences',
    ],
    categoryRelationshipScore: score,
    categoryLifestyleScore: score - 5,
    categoryMusicScore: score - 2,
    categoryQuestionScore: score - 8,
    categoryInterestScore: score - 3,
    categoryCommunicationScore: score - 1,
    distanceLabel: '12.4 km away',
  );
}

Widget _discoverDeck({required double cardHeight, DiscoveryCandidate? candidate}) {
  final c = candidate ?? _extremeCandidate();
  return Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _en.discoverBestMatchesTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            _en.discoverBestMatchesSubtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: DiscoveryProfileCard(
                candidate: c,
                onWhyTap: () {},
              ),
            ),
            const SizedBox(height: 16),
            DiscoveryActionButtons(
              onPass: () {},
              onSuperLike: () {},
              onLike: () {},
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 2.5 device matrix — auth login', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController(
        authRepository: FakeAuthRepository(),
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..start();
    });

    tearDown(() => controller.dispose());

    for (final device in _devices) {
      testWidgets('login ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device, 1.0);
        await tester.pumpWidget(_authApp(const LoginPage(), controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 2.5 — discover card extreme content', () {
    for (final device in _devices) {
      testWidgets('extreme card ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device, 1.0);
        await tester.pumpWidget(
          _withScale(
            Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _discoverDeck(cardHeight: device.h * 0.55),
                ),
              ),
            ),
            1.0,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    for (final score in [0, 1, 50, 99, 100]) {
      testWidgets('compatibility score $score on 360x640', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, _devices.first, 1.0);
        final candidate = _extremeCandidate(score: score).copyWith(
          compatibilityStatus: score > 0
              ? CompatibilityDisplayStatus.ready
              : CompatibilityDisplayStatus.unavailable,
        );
        await tester.pumpWidget(
          _withScale(
            Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    height: 520,
                    child: DiscoveryProfileCard(candidate: candidate),
                  ),
                ),
              ),
            ),
            1.0,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 2.5 — action buttons TR on narrow', () {
    testWidgets('375x667 Turkish labels', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, (w: 375, h: 667, label: '375x667'), 1.0);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('tr'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DiscoveryActionButtons(
                  onPass: () {},
                  onSuperLike: () {},
                  onLike: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(_tr.discoveryActionConnect), findsOneWidget);
    });
  });

  group('Phase 2.5 — font scaling discover deck', () {
    for (final scale in _textScales) {
      testWidgets('scale $scale on 360x640', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, _devices.first, scale);
        await tester.pumpWidget(
          _withScale(
            _discoverDeck(cardHeight: 360),
            scale,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 2.5 — dark mode snapshots', () {
    testWidgets('login dark 390x844', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, (w: 390, h: 844, label: '390x844'), 1.0);
      final controller = AuthController(
        authRepository: FakeAuthRepository(),
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..start();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        AppScope(
          config: const AppConfig(environment: AppEnvironment.development),
          logger: const AppLogger(environment: AppEnvironment.development),
          child: AuthScope(
            controller: controller,
            child: _withScale(const LoginPage(), 1.0, brightness: Brightness.dark),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('discover card dark 360x640', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first, 1.0);
      await tester.pumpWidget(
        _withScale(
          Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 520,
                  child: DiscoveryProfileCard(
                    candidate: _extremeCandidate(),
                    onWhyTap: () {},
                  ),
                ),
              ),
            ),
          ),
          1.0,
          brightness: Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.5 device matrix — auth screens narrow', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController(
        authRepository: FakeAuthRepository(),
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..start();
    });

    tearDown(() => controller.dispose());

    const narrowDevices = <_Size>[
      (w: 360, h: 640, label: '360x640'),
      (w: 375, h: 667, label: '375x667'),
    ];

    for (final device in narrowDevices) {
      testWidgets('register ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device, 1.0);
        await tester.pumpWidget(_authApp(const RegisterPage(), controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
      testWidgets('phone ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device, 1.0);
        await tester.pumpWidget(_authApp(const PhoneLoginScreen(), controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
      testWidgets('password_reset ${device.label}', (tester) async {
        addTearDown(() => _resetViewport(tester));
        await _configureViewport(tester, device, 1.0);
        await tester.pumpWidget(_authApp(const PasswordResetPage(), controller));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('Phase 2.5 — keyboard auth', () {
    late AuthController controller;

    setUp(() {
      controller = AuthController(
        authRepository: FakeAuthRepository(),
        userDocumentRepository: FakeUserDocumentRepository(),
        logger: const AppLogger(environment: AppEnvironment.development),
      )..start();
    });

    tearDown(() => controller.dispose());

    testWidgets('register form with keyboard 360x640', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first, 1.0);
      await tester.pumpWidget(_authApp(const RegisterPage(), controller));
      await tester.pumpAndSettle();

      final emailField = find.byType(TextField).first;
      await tester.ensureVisible(emailField);
      await tester.tap(emailField);
      await tester.pump();
      await tester.showKeyboard(emailField);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.5 — action buttons narrow EN', () {
    testWidgets('360x640 English labels', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first, 1.0);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: DiscoveryActionButtons(
                  onPass: () {},
                  onSuperLike: () {},
                  onLike: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('Phase 2.5 — system states', () {
    testWidgets('loading empty error', (tester) async {
      addTearDown(() => _resetViewport(tester));
      await _configureViewport(tester, _devices.first, 1.0);
      await tester.pumpWidget(
        _withScale(
          const Scaffold(
            body: Column(
              children: [
                Expanded(child: MevoraLoading.page()),
                Expanded(
                  child: MevoraEmptyState(
                    title: 'Empty',
                    message: 'No matches',
                  ),
                ),
                Expanded(
                  child: MevoraErrorView(
                    title: 'Error',
                    message: 'Failed',
                  ),
                ),
              ],
            ),
          ),
          1.0,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });
}
