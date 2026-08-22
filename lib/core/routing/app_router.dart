import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/presentation/pages/design_system_page.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/routing/auth_redirector.dart';
import 'package:mevora/core/routing/lazy_shell_navigator.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/settings/presentation/pages/blocked_users_page.dart';
import 'package:mevora/features/settings/presentation/pages/change_password_page.dart';
import 'package:mevora/features/settings/presentation/pages/discovery_preferences_page.dart';
import 'package:mevora/features/settings/presentation/pages/edit_profile_page.dart';
import 'package:mevora/features/settings/presentation/pages/location_settings_page.dart';
import 'package:mevora/features/settings/presentation/pages/privacy_settings_page.dart';
import 'package:mevora/features/settings/presentation/pages/settings_page.dart';
import 'package:mevora/features/authentication/presentation/pages/login_page.dart';
import 'package:mevora/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:mevora/features/authentication/presentation/pages/password_reset_page.dart';
import 'package:mevora/features/authentication/presentation/pages/register_page.dart';
import 'package:mevora/features/authentication/presentation/pages/splash_page.dart';
import 'package:mevora/features/authentication/presentation/screens/otp_verification_screen.dart';
import 'package:mevora/features/authentication/presentation/screens/phone_login_screen.dart';
import 'package:mevora/features/boost/presentation/pages/boost_screen.dart';
import 'package:mevora/features/calls/presentation/pages/call_pages.dart';
import 'package:mevora/features/chat/presentation/pages/chat_page.dart';
import 'package:mevora/features/discovery/presentation/pages/discovery_page.dart';
import 'package:mevora/features/location/presentation/controllers/location_controller.dart';
import 'package:mevora/features/location/presentation/pages/location_permission_page.dart';
import 'package:mevora/features/matching/presentation/pages/app_shell.dart';
import 'package:mevora/features/matching/presentation/pages/matches_page.dart';
import 'package:mevora/features/music/presentation/pages/music_page.dart';
import 'package:mevora/features/notifications/presentation/pages/notification_settings_page.dart';
import 'package:mevora/features/permissions/presentation/pages/privacy_permissions_page.dart';
import 'package:mevora/features/profile/presentation/pages/profile_tab_page.dart';
import 'package:mevora/features/safety/presentation/pages/report_page.dart';
import 'package:mevora/shared/animations/mevora_page_transitions.dart';

GoRouter createAppRouter({
  required AppConfig config,
  required AuthController authController,
  LocationController? locationController,
}) {
  final refresh = locationController == null
      ? authController
      : Listenable.merge(<Listenable>[authController, locationController]);
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      return AuthRedirector.redirect(
        status: authController.status,
        location: state.matchedLocation,
        allowDesignSystem: config.showDebugBanner,
        phoneChallengeActive:
            authController.phoneAuth.hasActiveChallenge ||
            authController.phoneChallenge != null,
        needsLocationOnboarding: locationController?.onboardingNeeded ?? false,
        locationGateResolved: locationController?.isResolved ?? true,
      );
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const SplashPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const LoginPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const RegisterPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.passwordReset,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const PasswordResetPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.phone,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const PhoneLoginScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.phoneOtp,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const OtpVerificationScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.locationPermission,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const LocationPermissionPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const OnboardingPage(),
        ),
      ),
      StatefulShellRoute(
        navigatorContainerBuilder: (context, navigationShell, children) {
          return LazyShellNavigator(
            currentIndex: navigationShell.currentIndex,
            children: children,
          );
        },
        pageBuilder: (context, state, navigationShell) {
          return MevoraPageTransitions.fadeSlide(
            key: state.pageKey,
            child: AppShell(navigationShell: navigationShell),
          );
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.discovery,
                pageBuilder: (context, state) =>
                    MevoraPageTransitions.fadeSlide(
                      key: state.pageKey,
                      cover: false,
                      child: const DiscoveryPage(),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.matches,
                pageBuilder: (context, state) =>
                    MevoraPageTransitions.fadeSlide(
                      key: state.pageKey,
                      cover: false,
                      child: const MatchesRoutePage(),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.music,
                pageBuilder: (context, state) =>
                    MevoraPageTransitions.fadeSlide(
                      key: state.pageKey,
                      cover: false,
                      child: const MusicPage(),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                pageBuilder: (context, state) =>
                    MevoraPageTransitions.fadeSlide(
                      key: state.pageKey,
                      cover: false,
                      child: const ProfileTabPage(),
                    ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.chat,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: ChatPage(matchId: state.pathParameters['matchId'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.incomingCall,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: IncomingCallPage(callId: state.pathParameters['callId'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.videoCall,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: VideoCallPage(callId: state.pathParameters['callId'] ?? ''),
        ),
      ),
      GoRoute(
        path: AppRoutes.report,
        pageBuilder: (context, state) {
          final params = state.uri.queryParameters;
          return MevoraPageTransitions.fadeSlide(
            key: state.pageKey,
            child: ReportPage(
              userId: params['userId'] ?? '',
              matchId: params['matchId'],
              messageId: params['messageId'],
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.boost,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const BoostScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const SettingsPage(),
        ),
        routes: [
          GoRoute(
            path: 'edit-profile',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const EditProfilePage(),
            ),
          ),
          GoRoute(
            path: 'change-password',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const ChangePasswordPage(),
            ),
          ),
          GoRoute(
            path: 'discovery-preferences',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const DiscoveryPreferencesPage(),
            ),
          ),
          GoRoute(
            path: 'location',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const LocationSettingsPage(),
            ),
          ),
          GoRoute(
            path: 'privacy-controls',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const PrivacySettingsPage(),
            ),
          ),
          GoRoute(
            path: 'blocked-users',
            pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
              key: state.pageKey,
              child: const BlockedUsersPage(),
            ),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.notificationSettings,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const NotificationSettingsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.privacyPermissions,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: const PrivacyPermissionsPage(),
        ),
      ),
      GoRoute(
        path: AppRoutes.designSystem,
        pageBuilder: (context, state) => MevoraPageTransitions.fadeSlide(
          key: state.pageKey,
          child: DesignSystemPage(config: config),
        ),
      ),
    ],
  );
}
