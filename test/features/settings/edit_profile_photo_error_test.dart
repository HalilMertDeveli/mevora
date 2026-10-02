import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/core/services/profile/profile_update_notifier.dart';
import 'package:mevora/core/testing/fake_permission_service.dart';
import 'package:mevora/core/theme/app_theme.dart';
import 'package:mevora/features/authentication/data/services/reauth_service.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/domain/entities/auth_user.dart';
import 'package:mevora/features/authentication/domain/repositories/user_document_repository.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/onboarding/domain/services/profile_photo_picker.dart';
import 'package:mevora/features/permissions/presentation/controllers/permission_controller.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/photo_upload_messages.dart';
import 'package:mevora/features/settings/data/services/profile_photo_manager.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/features/settings/presentation/pages/edit_profile_page.dart';
import 'package:mevora/l10n/app_localizations.dart';

import '../../helpers/fake_auth.dart';
import '../../helpers/fake_settings_hub_repository.dart';

class _SilentLogger implements AppLogger {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeUserDocs implements UserDocumentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future.value(null);
}

class _FakeReauth implements ReauthPort {
  @override
  Future<void> reauthenticateWithGoogle() async {}

  @override
  Future<void> reauthenticateWithPassword(String password) async {}
}

/// Accepts every photo it is given; what is under test is the page's own
/// message handling.
class _AcceptingPhotoManager implements ProfilePhotoManager {
  var added = 0;

  @override
  Future<Result<UserProfile>> addPhoto({
    required UserProfile profile,
    required String imageId,
    required List<int> bytes,
    required String contentType,
  }) async {
    added += 1;
    return Success(profile);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Refuses to make any photo the primary one, the way the real manager does
/// for a photo that has not been verified.
class _RefusingPrimaryManager extends _AcceptingPhotoManager {
  @override
  Future<Result<UserProfile>> setPrimaryPhoto({
    required UserProfile profile,
    required String photoId,
  }) async {
    return const Err(ValidationFailure(PhotoPolicy.primaryRequiresFaceAnchor));
  }
}

/// Loses every upload, as a dropped connection would.
class _FailingUploadManager extends _AcceptingPhotoManager {
  @override
  Future<Result<UserProfile>> addPhoto({
    required UserProfile profile,
    required String imageId,
    required List<int> bytes,
    required String contentType,
  }) async {
    return const Err(ValidationFailure(PhotoUploadMessages.failed));
  }
}

final _en = lookupAppLocalizations(const Locale('en'));

UserProfile _profile() {
  return const UserProfile(
    uid: 'u1',
    displayName: 'Halil',
    photos: [
      ProfilePhoto(id: '1', storagePath: 'a', isPrimary: true),
      ProfilePhoto(id: '2', storagePath: 'b', order: 1, isPrimary: false),
      ProfilePhoto(id: '3', storagePath: 'c', order: 2, isPrimary: false),
    ],
    onboardingCompleted: true,
    profileCompleted: true,
  );
}

Future<_AcceptingPhotoManager> _openEditProfile(
  WidgetTester tester, {
  Size size = const Size(1080, 12000),
  UserProfile? profile,
  _AcceptingPhotoManager? manager,
  ProfilePhotoPicker picker = const StubProfilePhotoPicker(
    next: PickedProfilePhoto(bytes: [1, 2, 3], contentType: 'image/jpeg'),
  ),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  const user = AuthUser(id: 'u1');
  final auth = AuthController(
    authRepository: FakeAuthRepository(user: user),
    userDocumentRepository: _FakeUserDocs(),
    logger: _SilentLogger(),
  );
  auth.user = user;
  auth.status = const Authenticated(user);

  final hub = FakeSettingsHubRepository()..profile = profile ?? _profile();
  final photos = manager ?? _AcceptingPhotoManager();
  final permissions = FakePermissionService(
    statuses: {PermissionType.photos: PermissionStatus.granted},
  );

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
        routes: [
          GoRoute(
            path: 'edit',
            builder: (context, state) => const EditProfilePage(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    AuthScope(
      controller: auth,
      child: PermissionScope(
        service: permissions,
        controller: PermissionController(service: permissions),
        child: SettingsScope(
          services: SettingsServices(
            settingsHub: hub,
            photoManager: photos,
            reauthService: _FakeReauth(),
            photoPicker: picker,
            profileUpdates: ProfileUpdateNotifier(),
          ),
          child: MaterialApp.router(
            theme: AppTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      ),
    ),
  );
  router.go('/edit');
  await tester.pumpAndSettle();
  return photos;
}

/// Add photo → Choose from gallery, up to the point the picker answers.
Future<void> _chooseFromGallery(WidgetTester tester) async {
  await tester.tap(find.text(_en.settingsAddPhoto));
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.addPhotoGallery));
  await tester.pumpAndSettle();
  // Photo access is granted in this harness. Whether a pre-prompt still shows
  // for a granted permission is a separate question, so pass it if it does.
  final allow = find.text(_en.permissionAllow);
  if (allow.evaluate().isNotEmpty) {
    await tester.tap(allow);
    await tester.pumpAndSettle();
  }
}

Future<void> _tryToRemoveAPhoto(WidgetTester tester) async {
  await tester.tap(find.byTooltip(_en.more).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(_en.settingsDeletePhoto));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'removing one of the last three photos is refused with a reason',
    (tester) async {
      await _openEditProfile(tester);

      await _tryToRemoveAPhoto(tester);

      expect(find.text(_en.settingsPhotoMinRequired), findsOneWidget);
    },
  );

  testWidgets('the refusal goes away once a photo is added', (tester) async {
    final photos = await _openEditProfile(tester);
    await _tryToRemoveAPhoto(tester);
    expect(find.text(_en.settingsPhotoMinRequired), findsOneWidget);

    await tester.tap(find.text(_en.settingsAddPhoto));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.addPhotoGallery));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.permissionAllow));
    await tester.pumpAndSettle();

    expect(photos.added, 1);
    expect(find.text(_en.settingsPhotoMinRequired), findsNothing);
  });

  testWidgets('closing the picker without a photo is not an error', (
    tester,
  ) async {
    // A stub with nothing to hand over answers the way a cancelled picker
    // does. That used to leave "Something went wrong" next to Save.
    await _openEditProfile(tester, picker: const StubProfilePhotoPicker());

    await _chooseFromGallery(tester);

    expect(find.text(_en.somethingWentWrong), findsNothing);
    expect(find.text(_en.photoNoneSelected), findsNothing);
  });

  testWidgets('a photo that fails to upload says so above the photos', (
    tester,
  ) async {
    await _openEditProfile(tester, manager: _FailingUploadManager());

    await _chooseFromGallery(tester);

    expect(find.text(_en.photoUploadFailed), findsOneWidget);
    expect(find.text(_en.somethingWentWrong), findsNothing);
  });

  testWidgets(
    'a refusal is on screen on a small phone with a full photo list',
    (tester) async {
      // 720x1600 at 2x: the size the defect was found on. With six photos the
      // list alone is taller than the screen, so a reason rendered under it was
      // never seen and the tap looked like it did nothing.
      const screen = Size(360, 800);
      await _openEditProfile(
        tester,
        size: screen,
        manager: _RefusingPrimaryManager(),
        profile: const UserProfile(
          uid: 'u1',
          displayName: 'Halil',
          photos: [
            ProfilePhoto(id: '1', storagePath: 'a', isPrimary: true),
            ProfilePhoto(id: '2', storagePath: 'b', order: 1, isPrimary: false),
            ProfilePhoto(id: '3', storagePath: 'c', order: 2, isPrimary: false),
            ProfilePhoto(id: '4', storagePath: 'd', order: 3, isPrimary: false),
            ProfilePhoto(id: '5', storagePath: 'e', order: 4, isPrimary: false),
            ProfilePhoto(id: '6', storagePath: 'f', order: 5, isPrimary: false),
          ],
          onboardingCompleted: true,
          profileCompleted: true,
        ),
      );

      final reason = find.text(_en.faceAnchorPrimaryRequiresVerify);
      Future<void> askToMakePrimary(int photoIndex) async {
        await tester.tap(find.byTooltip(_en.more).at(photoIndex));
        await tester.pumpAndSettle();
        await tester.tap(find.text(_en.settingsSetPrimaryPhoto));
        await tester.pumpAndSettle();
      }

      void expectReasonOnScreen() {
        expect(reason, findsOneWidget);
        final rect = tester.getRect(reason);
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(screen.height));
      }

      // From the top of the page, untouched: the reason used to sit under all
      // six photos, below the fold.
      await askToMakePrimary(1);
      expectReasonOnScreen();

      // From further down the list: the page comes back up to the reason.
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pumpAndSettle();
      await askToMakePrimary(4);
      expectReasonOnScreen();
    },
  );
}
