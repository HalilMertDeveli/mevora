import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:mevora/features/app_operations/domain/app_operations_repository.dart';

/// The app's view of the server-owned operations document: maintenance,
/// required and recommended updates, an announcement, feature switches.
///
/// It never blocks startup. [start] applies the last valid document from the
/// device cache synchronously (or normal operation when there is none), then
/// follows the live document. A failed read keeps whatever was last valid —
/// an outage of this document must never itself become an outage.
class AppOperationsController extends ChangeNotifier
    with WidgetsBindingObserver {
  AppOperationsController({
    required AppOperationsRepository repository,
    required AppOperationsStore store,
    required AppVersionProvider versionProvider,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _repository = repository,
       _store = store,
       _versionProvider = versionProvider,
       _logger = logger,
       _clock = clock ?? DateTime.now;

  final AppOperationsRepository _repository;
  final AppOperationsStore _store;
  final AppVersionProvider _versionProvider;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  AppOperationsConfig _config = AppOperationsConfig.defaults;
  InstalledApp? _installed;
  String? _dismissedAnnouncementId;
  String? _dismissedRecommendedVersion;
  StreamSubscription<AppOperationsConfig>? _subscription;
  Timer? _boundaryTimer;
  bool _started = false;
  bool _observing = false;
  bool _disposed = false;
  final _RoutingNotifier _routing = _RoutingNotifier();
  (AppOperationsGate, bool)? _routingKey;

  /// Longest single wait for an announcement boundary; longer waits re-arm.
  static const Duration _maxTimer = Duration(hours: 12);

  AppOperationsConfig get config => _config;

  /// Null until the installed version has been read.
  InstalledApp? get installed => _installed;

  AppPlatform get platform => _installed?.platform ?? AppPlatform.other;

  VersionGate get versionGate {
    final installed = _installed;
    if (installed == null) {
      return VersionGate.ok;
    }
    return _config.versionGateFor(
      platform: installed.platform,
      installed: installed.version,
    );
  }

  AppOperationsGate get gate =>
      resolveAppOperationsGate(config: _config, versionGate: versionGate);

  /// The server's maintenance copy, or null to use the app's own.
  String? get maintenanceMessage => _config.maintenanceMessage;

  /// The store link for this platform, when the document provides one.
  String? get updateUrl => _config.updateUrl.forPlatform(platform);

  bool isFeatureEnabled(AppFeature feature) =>
      _config.isFeatureEnabled(feature);

  /// The announcement to show now: active and not dismissed on this device.
  AppAnnouncement? get activeAnnouncement {
    final announcement = _config.announcement;
    if (announcement == null ||
        !announcement.isActiveAt(_clock()) ||
        announcement.id == _dismissedAnnouncementId) {
      return null;
    }
    return announcement;
  }

  /// A newer version is recommended and this one has not been waved off.
  bool get showUpdateRecommendation {
    if (versionGate != VersionGate.updateRecommended) {
      return false;
    }
    final recommended = _config.recommendedVersion.forPlatform(platform);
    return recommended != null && recommended != _dismissedRecommendedVersion;
  }

  /// Fires only when something the router reads changes — the gate or the
  /// Humor Lab switch — so an announcement never makes pages rebuild.
  Listenable get routing => _routing;

  void start() {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    try {
      final cached = _store.readConfig();
      if (cached != null) {
        _config = cached;
      }
      _dismissedAnnouncementId = _store.readDismissedAnnouncementId();
      _dismissedRecommendedVersion = _store.readDismissedRecommendedVersion();
    } on Object catch (error, stackTrace) {
      _logger?.warning(
        'App operations cache unreadable',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _changed();
    unawaited(_resolveInstalled());
    _subscribe();
  }

  void attachLifecycle() {
    if (_observing || _disposed) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  void detachLifecycle() {
    if (!_observing) {
      return;
    }
    WidgetsBinding.instance.removeObserver(this);
    _observing = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      refresh();
    }
  }

  /// Re-evaluates time windows and re-opens the live document if an error
  /// closed it. Called on resume.
  void refresh() {
    if (!_started || _disposed) {
      return;
    }
    if (_subscription == null) {
      _subscribe();
    }
    _changed();
  }

  Future<void> dismissAnnouncement() async {
    final announcement = activeAnnouncement;
    if (announcement == null) {
      return;
    }
    _dismissedAnnouncementId = announcement.id;
    _changed();
    try {
      await _store.writeDismissedAnnouncementId(announcement.id);
    } on Object catch (error) {
      _logger?.warning(
        'Could not remember dismissed announcement',
        error: error,
      );
    }
  }

  Future<void> dismissUpdateRecommendation() async {
    final recommended = _config.recommendedVersion.forPlatform(platform);
    if (recommended == null) {
      return;
    }
    _dismissedRecommendedVersion = recommended;
    _changed();
    try {
      await _store.writeDismissedRecommendedVersion(recommended);
    } on Object catch (error) {
      _logger?.warning('Could not remember dismissed update', error: error);
    }
  }

  Future<void> _resolveInstalled() async {
    try {
      final installed = await _versionProvider.installed();
      if (_disposed) {
        return;
      }
      _installed = installed;
      _changed();
    } on Object catch (error) {
      _logger?.warning('Installed version unavailable', error: error);
    }
  }

  void _subscribe() {
    try {
      _subscription = _repository.watch().listen(
        _onConfig,
        onError: _onError,
        onDone: () => _subscription = null,
      );
    } on Object catch (error, stackTrace) {
      _onError(error, stackTrace);
    }
  }

  void _onConfig(AppOperationsConfig config) {
    if (_disposed) {
      return;
    }
    unawaited(_cache(config));
    if (config == _config) {
      return;
    }
    _config = config;
    _changed();
  }

  Future<void> _cache(AppOperationsConfig config) async {
    try {
      await _store.writeConfig(config);
    } on Object catch (error) {
      _logger?.warning('Could not cache app operations', error: error);
    }
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    // Keep the last valid document. The listener is finished after an error,
    // so drop it; the next resume opens a fresh one.
    _logger?.warning(
      'App operations stream failed; keeping last valid config',
      error: error,
      stackTrace: stackTrace,
    );
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  void _changed() {
    if (_disposed) {
      return;
    }
    _armBoundaryTimer();
    notifyListeners();
    final key = (gate, isFeatureEnabled(AppFeature.humorLab));
    if (key != _routingKey) {
      _routingKey = key;
      _routing.ping();
    }
  }

  /// Wakes up when the announcement enters or leaves its window, so it
  /// appears and disappears on time without a new document.
  void _armBoundaryTimer() {
    _boundaryTimer?.cancel();
    _boundaryTimer = null;
    final now = _clock();
    final next = _config.announcement?.nextBoundaryAfter(now);
    if (next == null) {
      return;
    }
    var wait = next.difference(now) + const Duration(milliseconds: 50);
    if (wait > _maxTimer) {
      wait = _maxTimer;
    }
    _boundaryTimer = Timer(wait, _changed);
  }

  @override
  void dispose() {
    _disposed = true;
    detachLifecycle();
    _boundaryTimer?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    _routing.dispose();
    super.dispose();
  }
}

class _RoutingNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}
