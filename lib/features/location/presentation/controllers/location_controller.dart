import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_messages.dart';
import 'package:mevora/core/services/location/location_accuracy_kind.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/location/data/location_analytics.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/entities/location_screen_state.dart';
import 'package:mevora/features/location/domain/location_onboarding_gate.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/domain/services/location_update_policy.dart';
import 'package:mevora/features/location/domain/usecases/location_usecases.dart';

class LocationController extends ChangeNotifier with WidgetsBindingObserver {
  LocationController({
    required this.repository,
    LocationAnalytics analytics = const NoOpLocationAnalytics(),
    LocationUpdatePolicy policy = const LocationUpdatePolicy(),
    this.successHold = const Duration(milliseconds: 900),
    DateTime Function()? clock,
  }) : _analytics = analytics,
       _requestPermission = RequestLocationPermission(repository),
       _getCurrentLocation = GetCurrentLocation(repository),
       _getPermissionStatus = GetLocationPermissionStatus(repository),
       _saveUserLocation = SaveUserLocation(repository),
       _updateUserLocation = UpdateUserLocation(
         repository,
         policy: policy,
         clock: clock,
       );

  final LocationRepository repository;
  final LocationAnalytics _analytics;
  final RequestLocationPermission _requestPermission;
  final GetCurrentLocation _getCurrentLocation;
  final GetLocationPermissionStatus _getPermissionStatus;
  final SaveUserLocation _saveUserLocation;
  final UpdateUserLocation _updateUserLocation;
  final Duration successHold;

  LocationScreenState screen = LocationScreenState.prompt;
  String? errorMessage;
  String? selectedCity;
  bool onboardingNeeded = false;
  bool isResolved = false;
  bool reducedAccuracy = false;
  bool isBusy = false;

  String? _uid;
  int _syncGeneration = 0;
  bool _observingLifecycle = false;
  bool _nativePromptedThisSession = false;

  String? get uid => _uid;

  void attachLifecycle() {
    if (_observingLifecycle) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(onAppResumed());
    }
  }

  Future<void> syncForUser(String? uid) async {
    if (uid == _uid && isResolved) {
      return;
    }
    final generation = ++_syncGeneration;
    _uid = uid;
    if (uid == null) {
      onboardingNeeded = false;
      isResolved = true;
      screen = LocationScreenState.prompt;
      errorMessage = null;
      notifyListeners();
      return;
    }

    isResolved = false;
    onboardingNeeded = false;
    notifyListeners();

    final flagsResult = await repository.loadLocationFlags(uid);
    final storedResult = await repository.loadOwnerLocation(uid);
    if (generation != _syncGeneration) {
      return;
    }

    final flags = flagsResult.valueOrNull ?? LocationFlags(uid: uid);
    final stored = storedResult.valueOrNull;
    onboardingNeeded = LocationOnboardingGate.shouldShow(
      locationOnboardingCompleted: flags.locationOnboardingCompleted,
      hasStoredLocation: stored != null,
    );
    if (onboardingNeeded) {
      await _refreshPromptState();
    }
    isResolved = true;
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    await _refreshPromptState();
    notifyListeners();
  }

  Future<void> allow() async {
    if (isBusy) {
      return;
    }
    isBusy = true;
    errorMessage = null;
    notifyListeners();

    try {
      await _analytics.permissionRequested();
      final result = await _requestPermission();
      if (result.isError) {
        final failure = result.failureOrNull;
        if (failure is LocationFailure &&
            failure.kind == LocationErrorKind.gpsDisabled) {
          screen = LocationScreenState.serviceDisabled;
          await _analytics.servicesDisabled();
          return;
        }
        await _setError(failure);
        return;
      }

      _nativePromptedThisSession = true;
      final status = result.valueOrNull ?? LocationPermissionStatus.denied;
      if (status == LocationPermissionStatus.granted) {
        await _analytics.permissionGranted();
        await _captureAndSave();
        return;
      }
      if (status.isDeniedForever) {
        screen = status == LocationPermissionStatus.restricted
            ? LocationScreenState.restricted
            : LocationScreenState.deniedForever;
        await _analytics.permissionDeniedForever();
        return;
      }
      screen = LocationScreenState.denied;
      await _analytics.permissionDenied();
    } on Object {
      await _setError(null);
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> retryDenied() async {
    if (isBusy) {
      return;
    }
    if (_nativePromptedThisSession &&
        screen == LocationScreenState.deniedForever) {
      await openAppSettings();
      return;
    }
    await allow();
  }

  Future<void> skip() async {
    final uid = _uid;
    if (uid == null || isBusy) {
      return;
    }
    isBusy = true;
    notifyListeners();
    try {
      await repository.saveLocationFlags(
        LocationFlags(
          uid: uid,
          locationEnabled: false,
          locationOnboardingCompleted: true,
        ),
      );
      _completeOnboarding();
    } on Object {
      _completeOnboarding();
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> continueWithCity(String city) async {
    selectedCity = city.trim();
    await skip();
  }

  Future<void> openAppSettings() async {
    await repository.openAppSettings();
  }

  Future<void> openLocationSettings() async {
    await repository.openGpsSettings();
  }

  Future<void> onAppResumed() async {
    final uid = _uid;
    if (uid == null) {
      return;
    }

    if (onboardingNeeded &&
        (screen == LocationScreenState.serviceDisabled ||
            screen == LocationScreenState.deniedForever ||
            screen == LocationScreenState.restricted ||
            screen == LocationScreenState.denied)) {
      await _refreshPromptState();
      if (screen == LocationScreenState.prompt) {
        notifyListeners();
      }
      return;
    }

    final flags = (await repository.loadLocationFlags(uid)).valueOrNull;
    if (flags == null || !flags.locationEnabled) {
      return;
    }
    final status = await _getPermissionStatus();
    if (status != LocationPermissionStatus.granted) {
      return;
    }
    final updated = await _updateUserLocation(uid: uid);
    if (updated.isError) {
      await _analytics.error(kind: _kindName(updated.failureOrNull));
    }
  }

  Future<void> _captureAndSave() async {
    final uid = _uid;
    if (uid == null) {
      await _setError(null);
      return;
    }

    screen = LocationScreenState.locating;
    notifyListeners();

    final accuracy = await repository.checkAccuracy();
    reducedAccuracy = accuracy == LocationAccuracyKind.reduced;

    final captured = await _getCurrentLocation();
    final position = captured.valueOrNull;
    if (position == null) {
      await _setError(captured.failureOrNull);
      return;
    }

    screen = LocationScreenState.preparingMatches;
    notifyListeners();

    final saved = await _saveUserLocation(uid: uid, position: position);
    if (saved.isError) {
      await _setError(saved.failureOrNull);
      return;
    }

    await _analytics.acquired();
    screen = reducedAccuracy
        ? LocationScreenState.reducedAccuracy
        : LocationScreenState.success;
    notifyListeners();
    if (successHold > Duration.zero) {
      await Future<void>.delayed(successHold);
    }
    _completeOnboarding();
  }

  Future<void> _refreshPromptState() async {
    final status = await _getPermissionStatus();
    reducedAccuracy = false;
    errorMessage = null;
    screen = switch (status) {
      LocationPermissionStatus.serviceDisabled =>
        LocationScreenState.serviceDisabled,
      LocationPermissionStatus.permanentlyDenied =>
        LocationScreenState.deniedForever,
      LocationPermissionStatus.restricted => LocationScreenState.restricted,
      LocationPermissionStatus.error => LocationScreenState.error,
      LocationPermissionStatus.granted => LocationScreenState.prompt,
      LocationPermissionStatus.denied => _nativePromptedThisSession
          ? LocationScreenState.denied
          : LocationScreenState.prompt,
      _ => LocationScreenState.prompt,
    };
  }

  Future<void> _setError(Failure? failure) async {
    await _analytics.error(kind: _kindName(failure));
    if (failure is LocationFailure) {
      screen = switch (failure.kind) {
        LocationErrorKind.gpsDisabled => LocationScreenState.serviceDisabled,
        LocationErrorKind.permissionDenied => LocationScreenState.denied,
        LocationErrorKind.permissionPermanentlyDenied =>
          LocationScreenState.deniedForever,
        LocationErrorKind.timeout ||
        LocationErrorKind.network ||
        LocationErrorKind.unavailable ||
        LocationErrorKind.invalidCoordinates ||
        LocationErrorKind.error => LocationScreenState.error,
      };
    } else {
      screen = LocationScreenState.error;
    }
    errorMessage = failure == null
        ? FailureMessages.of(
            const LocationFailure(
              'Location is currently unavailable.',
              kind: LocationErrorKind.error,
            ),
          )
        : FailureMessages.of(failure);
  }

  void _completeOnboarding() {
    onboardingNeeded = false;
    isResolved = true;
    notifyListeners();
  }

  String _kindName(Failure? failure) {
    if (failure is LocationFailure) {
      return failure.kind.name;
    }
    return 'error';
  }

  @override
  void dispose() {
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    super.dispose();
  }
}
