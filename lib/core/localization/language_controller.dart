import 'dart:async';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/language_repository.dart';

typedef AuthLocaleBinder = Future<void> Function(String languageCode);

/// Owns the active [Locale]. Widgets read [locale]; they do not resolve language.
class LanguageController extends ChangeNotifier {
  LanguageController({
    required LanguageRepository repository,
    Locale? deviceLocale,
    this.authLocaleBinder,
    this.analytics,
  }) : _repository = repository,
       _deviceLocale = deviceLocale ?? PlatformDispatcher.instance.locale;

  final LanguageRepository _repository;
  final Locale _deviceLocale;
  final AuthLocaleBinder? authLocaleBinder;
  final AnalyticsProvider? analytics;

  AppLanguage _language = AppLanguage.fallback;
  bool _loaded = false;
  String? _uid;

  /// What the last remote sync wrote (or is writing), so an unchanged
  /// uid + language is not synced again.
  String? _syncedUid;
  String? _syncedCode;

  bool get isLoaded => _loaded;

  AppLanguage get language => _language;

  String get languageCode => _language.code;

  Locale get locale => _language.locale;

  /// Priority: 1) saved local preference 2) device language 3) English.
  Future<void> load() async {
    final saved = await _repository.loadSaved();
    _language = saved ?? AppLanguage.fromDeviceLocale(_deviceLocale);
    _loaded = true;
    if (saved == null) {
      await _repository.saveLocal(_language);
    }
    notifyListeners();
    unawaited(_applyAuthLocale());
  }

  /// Live language switch. Local write always wins; Firebase is best-effort.
  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language && _loaded) {
      return;
    }
    _language = language;
    _loaded = true;
    notifyListeners();
    await _repository.saveLocal(language);
    unawaited(_applyAuthLocale());
    unawaited(_syncRemote());
    unawaited(
      analytics?.logEvent(
        'language_changed',
        parameters: {'languageCode': language.code},
      ),
    );
  }

  /// After login, push the local preference to `userSettings/{uid}`.
  /// Does not overwrite local language from Firebase.
  ///
  /// The app calls this on every auth-controller notification, which fires
  /// for each users/profiles snapshot. Each sync is a read plus a full write
  /// of the settings doc, so it runs once per signed-in uid and language.
  Future<void> attachUser(String uid) async {
    _uid = uid;
    if (_syncedUid == uid && _syncedCode == _language.code) {
      return;
    }
    await _syncRemote();
  }

  /// Logout must keep the local language preference.
  void detachUser() {
    _uid = null;
    _syncedUid = null;
    _syncedCode = null;
  }

  Future<void> _syncRemote() async {
    final uid = _uid;
    if (uid == null) {
      return;
    }
    final code = _language.code;
    // Claimed before the await so overlapping calls do not sync twice.
    _syncedUid = uid;
    _syncedCode = code;
    try {
      await _repository.syncToRemote(uid: uid, language: _language);
    } on Object {
      // Offline / permission errors must not roll back the local UI language.
      // Forget the claim so the next attach retries.
      if (_syncedUid == uid && _syncedCode == code) {
        _syncedUid = null;
        _syncedCode = null;
      }
    }
  }

  Future<void> _applyAuthLocale() async {
    final binder = authLocaleBinder;
    if (binder == null) {
      return;
    }
    try {
      await binder(_language.code);
    } on Object {
      // SMS locale is best-effort; UI language already applied.
    }
  }
}
