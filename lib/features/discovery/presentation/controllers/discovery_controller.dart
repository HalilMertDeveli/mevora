import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/services/location/location_permission_status.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_candidate.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/location/domain/entities/location_flags.dart';
import 'package:mevora/features/location/domain/repositories/location_repository.dart';
import 'package:mevora/features/location/domain/services/location_update_policy.dart';

enum LocationPromptPhase {
  /// Custom Mevora explanation. Native GPS dialog has not been shown.
  explanation,
  gpsDisabled,
  permanentlyDenied,
  error,
  ready,
}

class DiscoveryFeedState {
  const DiscoveryFeedState({
    this.phase = LocationPromptPhase.explanation,
    this.candidates = const [],
    this.radius = DiscoveryRadius.km25,
    this.isLoading = false,
    this.errorMessage,
    this.showLikeBurst = false,
    this.matchedCandidate,
    this.activeBoost,
  });

  final LocationPromptPhase phase;
  final List<DiscoveryCandidate> candidates;
  final DiscoveryRadius radius;
  final bool isLoading;
  final String? errorMessage;
  final bool showLikeBurst;
  final DiscoveryCandidate? matchedCandidate;
  final Boost? activeBoost;

  DiscoveryCandidate? get current =>
      candidates.isEmpty ? null : candidates.first;

  DiscoveryFeedState copyWith({
    LocationPromptPhase? phase,
    List<DiscoveryCandidate>? candidates,
    DiscoveryRadius? radius,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    bool? showLikeBurst,
    DiscoveryCandidate? matchedCandidate,
    bool clearMatch = false,
    Boost? activeBoost,
    bool clearBoost = false,
  }) {
    return DiscoveryFeedState(
      phase: phase ?? this.phase,
      candidates: candidates ?? this.candidates,
      radius: radius ?? this.radius,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      showLikeBurst: showLikeBurst ?? this.showLikeBurst,
      matchedCandidate: clearMatch
          ? null
          : (matchedCandidate ?? this.matchedCandidate),
      activeBoost: clearBoost ? null : (activeBoost ?? this.activeBoost),
    );
  }
}

/// Presentation talks to repositories only. No GPS APIs, no other-user coords.
class DiscoveryController extends ChangeNotifier {
  DiscoveryController({
    required this.uid,
    required LocationRepository locationRepository,
    required DiscoveryRepository discoveryRepository,
    PurchaseRepository? purchaseRepository,
    LocationSyncCoordinator? locationSync,
    bool skipExplanationIfAlreadyGranted = true,
  }) : _locationRepository = locationRepository,
       _discoveryRepository = discoveryRepository,
       _purchaseRepository = purchaseRepository,
       _locationSync = locationSync ?? LocationSyncCoordinator(),
       _skipExplanationIfAlreadyGranted = skipExplanationIfAlreadyGranted;

  final String uid;
  final LocationRepository _locationRepository;
  final DiscoveryRepository _discoveryRepository;
  final PurchaseRepository? _purchaseRepository;
  final LocationSyncCoordinator _locationSync;
  final bool _skipExplanationIfAlreadyGranted;

  PurchaseRepository? get purchaseRepository => _purchaseRepository;

  DiscoveryFeedState state = const DiscoveryFeedState();
  bool declinedLocation = false;

  Future<void> start() async {
    unawaited(refreshBoost());
    final flags = (await _locationRepository.loadLocationFlags(uid)).valueOrNull;
    if (flags?.locationOnboardingCompleted == true) {
      declinedLocation = flags?.locationEnabled != true;
      state = state.copyWith(phase: LocationPromptPhase.ready);
      notifyListeners();
      await loadCandidates();
      return;
    }
    final permission = await _locationRepository.checkPermission();
    final gpsOn = await _locationRepository.isGpsEnabled();
    if (permission == LocationPermissionStatus.granted && gpsOn) {
      if (_skipExplanationIfAlreadyGranted) {
        await _captureAndLoad();
        return;
      }
    }
    if (permission == LocationPermissionStatus.permanentlyDenied) {
      state = state.copyWith(phase: LocationPromptPhase.permanentlyDenied);
      notifyListeners();
      await loadCandidates();
      return;
    }
    if (!gpsOn && permission == LocationPermissionStatus.granted) {
      state = state.copyWith(phase: LocationPromptPhase.gpsDisabled);
      notifyListeners();
      await loadCandidates();
      return;
    }
    state = state.copyWith(phase: LocationPromptPhase.explanation);
    notifyListeners();
  }

  Future<void> useMyLocation() async {
    state = state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    final gpsOn = await _locationRepository.isGpsEnabled();
    if (!gpsOn) {
      state = state.copyWith(
        phase: LocationPromptPhase.gpsDisabled,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    final permission = await _locationRepository.requestPermission();
    if (permission == LocationPermissionStatus.permanentlyDenied) {
      state = state.copyWith(
        phase: LocationPromptPhase.permanentlyDenied,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    if (permission != LocationPermissionStatus.granted) {
      declinedLocation = true;
      state = state.copyWith(
        phase: LocationPromptPhase.ready,
        isLoading: false,
      );
      notifyListeners();
      await loadCandidates();
      return;
    }
    await _captureAndLoad();
  }

  Future<void> skipLocation() async {
    declinedLocation = true;
    await _locationRepository.saveLocationFlags(
      LocationFlags(
        uid: uid,
        locationEnabled: false,
        locationOnboardingCompleted: true,
      ),
    );
    state = state.copyWith(phase: LocationPromptPhase.ready, clearError: true);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> openSettings() async {
    await _locationRepository.openAppSettings();
  }

  Future<void> openGpsSettings() async {
    await _locationRepository.openGpsSettings();
  }

  Future<void> setRadius(DiscoveryRadius radius) async {
    state = state.copyWith(radius: radius);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> refresh() async {
    if (!declinedLocation) {
      final permission = await _locationRepository.checkPermission();
      if (permission == LocationPermissionStatus.granted) {
        await _maybePersistLocation();
      }
    }
    await loadCandidates();
  }

  Future<void> loadCandidates() async {
    state = state.copyWith(isLoading: true, clearError: true);
    notifyListeners();
    final result = await _discoveryRepository.getCandidates(
      radius: state.radius,
    );
    switch (result) {
      case Success(:final value):
        state = state.copyWith(
          candidates: value.candidates,
          isLoading: false,
          phase: state.phase == LocationPromptPhase.explanation
              ? LocationPromptPhase.ready
              : state.phase,
        );
      case Err(:final failure):
        state = state.copyWith(
          isLoading: false,
          errorMessage: failure.message,
          phase: LocationPromptPhase.error,
        );
    }
    notifyListeners();
  }

  Future<void> decide(DiscoveryDecision decision) async {
    final current = state.current;
    if (current == null) {
      return;
    }
    if (decision == DiscoveryDecision.like ||
        decision == DiscoveryDecision.superLike) {
      state = state.copyWith(showLikeBurst: true);
      notifyListeners();
    }
    final result = await _discoveryRepository.recordDecision(
      candidateUid: current.uid,
      decision: decision,
    );
    final remaining = state.candidates.skip(1).toList();
    final matched = result.valueOrNull?.matched == true ? current : null;
    state = state.copyWith(
      candidates: remaining,
      showLikeBurst: false,
      matchedCandidate: matched,
      clearMatch: matched == null,
    );
    notifyListeners();
    if (remaining.isEmpty) {
      await loadCandidates();
    }
  }

  void clearMatch() {
    state = state.copyWith(clearMatch: true);
    notifyListeners();
  }

  Future<void> _captureAndLoad() async {
    await _maybePersistLocation();
    state = state.copyWith(phase: LocationPromptPhase.ready, isLoading: false);
    notifyListeners();
    await loadCandidates();
  }

  Future<void> _maybePersistLocation() async {
    final result = await _locationRepository.captureCurrentLocation();
    switch (result) {
      case Success(:final value):
        if (_locationSync.shouldPersist(value)) {
          final persisted = await _locationRepository.persistOwnerLocation(
            uid: uid,
            position: value,
          );
          if (persisted.isSuccess) {
            _locationSync.markPersisted(value);
          }
        }
      case Err(:final failure):
        if (failure is LocationFailure) {
          state = state.copyWith(phase: _phaseFor(failure.kind));
        }
    }
  }

  /// Cached Boost for the Boost button. Not called on every swipe.
  Future<void> refreshBoost() async {
    final repo = _purchaseRepository;
    if (repo == null) {
      return;
    }
    final result = await repo.getActiveBoost(uid);
    final boost = result.valueOrNull;
    if (boost == null) {
      if (state.activeBoost != null) {
        state = state.copyWith(clearBoost: true);
        notifyListeners();
      }
      return;
    }
    state = state.copyWith(activeBoost: boost);
    notifyListeners();
  }

  LocationPromptPhase _phaseFor(LocationErrorKind kind) {
    return switch (kind) {
      LocationErrorKind.gpsDisabled => LocationPromptPhase.gpsDisabled,
      LocationErrorKind.permissionPermanentlyDenied =>
        LocationPromptPhase.permanentlyDenied,
      LocationErrorKind.timeout ||
      LocationErrorKind.unavailable ||
      LocationErrorKind.network ||
      LocationErrorKind.invalidCoordinates ||
      LocationErrorKind.error => LocationPromptPhase.error,
      LocationErrorKind.permissionDenied => LocationPromptPhase.ready,
    };
  }
}
