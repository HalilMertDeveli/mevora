import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/language_controller.dart';
import 'package:mevora/core/localization/language_repository.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/user_settings_repository.dart';

class FakeUserSettingsRepository implements UserSettingsRepository {
  FakeUserSettingsRepository({this.throwOnSave = false});

  final bool throwOnSave;
  final Map<String, String> saved = {};
  int saveCalls = 0;

  @override
  Future<UserSettings> load(String uid) async {
    return UserSettings(
      uid: uid,
      languageCode: saved[uid] ?? 'en',
    );
  }

  @override
  Future<void> save(UserSettings settings) async {
    await saveLanguageCode(settings.uid, settings.languageCode);
  }

  @override
  Future<void> saveLanguageCode(String uid, String languageCode) async {
    saveCalls++;
    if (throwOnSave) {
      throw StateError('offline');
    }
    saved[uid] = languageCode;
  }
}

void main() {
  test('device Turkish becomes tr; English becomes en; any other becomes tr', () {
    expect(
      AppLanguage.fromDeviceLocale(const Locale('tr')),
      AppLanguage.turkish,
    );
    expect(
      AppLanguage.fromDeviceLocale(const Locale('tr', 'TR')),
      AppLanguage.turkish,
    );
    expect(
      AppLanguage.fromDeviceLocale(const Locale('en')),
      AppLanguage.english,
    );
    expect(
      AppLanguage.fromDeviceLocale(const Locale('de')),
      AppLanguage.turkish,
    );
    expect(
      AppLanguage.fromDeviceLocale(const Locale('fr', 'FR')),
      AppLanguage.turkish,
    );
  });

  test('fromCode only accepts tr and en; unknown falls back to Turkish', () {
    expect(AppLanguage.fromCode('tr'), AppLanguage.turkish);
    expect(AppLanguage.fromCode('TR'), AppLanguage.turkish);
    expect(AppLanguage.fromCode('en-US'), AppLanguage.english);
    expect(AppLanguage.fromCode('de'), AppLanguage.turkish);
    expect(AppLanguage.fromCode(null), AppLanguage.turkish);
  });

  test('first launch with no saved preference uses device then persists', () async {
    final local = MemoryLanguageDataSource();
    final controller = LanguageController(
      repository: LanguageRepository(local: local),
      deviceLocale: const Locale('tr', 'TR'),
    );
    await controller.load();
    expect(controller.language, AppLanguage.turkish);
    expect(await local.readLanguageCode(), 'tr');
  });

  test('German device with no saved preference becomes Turkish (default)', () async {
    final controller = LanguageController(
      repository: LanguageRepository(local: MemoryLanguageDataSource()),
      deviceLocale: const Locale('de'),
    );
    await controller.load();
    expect(controller.languageCode, 'tr');
  });

  test('saved preference wins over device language', () async {
    final controller = LanguageController(
      repository: LanguageRepository(
        local: MemoryLanguageDataSource(languageCode: 'en'),
      ),
      deviceLocale: const Locale('tr'),
    );
    await controller.load();
    expect(controller.language, AppLanguage.english);
  });

  test('saved tr is restored on restart even if device is English', () async {
    final local = MemoryLanguageDataSource(languageCode: 'tr');
    final first = LanguageController(
      repository: LanguageRepository(local: local),
      deviceLocale: const Locale('en'),
    );
    await first.load();
    expect(first.languageCode, 'tr');

    final restarted = LanguageController(
      repository: LanguageRepository(local: local),
      deviceLocale: const Locale('de'),
    );
    await restarted.load();
    expect(restarted.languageCode, 'tr');
  });

  test('manual change updates local store and live locale', () async {
    final local = MemoryLanguageDataSource();
    final controller = LanguageController(
      repository: LanguageRepository(local: local),
      deviceLocale: const Locale('en'),
    );
    await controller.load();
    await controller.setLanguage(AppLanguage.turkish);
    expect(controller.locale, const Locale('tr'));
    expect(await local.readLanguageCode(), 'tr');
  });

  test('logout keeps the local language preference', () async {
    final local = MemoryLanguageDataSource(languageCode: 'tr');
    final remote = FakeUserSettingsRepository();
    final controller = LanguageController(
      repository: LanguageRepository(local: local, remote: remote),
      deviceLocale: const Locale('en'),
    );
    await controller.load();
    await controller.attachUser('u1');
    expect(remote.saved['u1'], 'tr');
    controller.detachUser();
    expect(controller.languageCode, 'tr');
    expect(await local.readLanguageCode(), 'tr');
  });

  test('login syncs local language to Firebase', () async {
    final remote = FakeUserSettingsRepository();
    final controller = LanguageController(
      repository: LanguageRepository(
        local: MemoryLanguageDataSource(languageCode: 'en'),
        remote: remote,
      ),
      deviceLocale: const Locale('tr'),
    );
    await controller.load();
    await controller.attachUser('u2');
    expect(remote.saved['u2'], 'en');
    expect(remote.saveCalls, 1);
  });

  test('Firebase write failure still applies the local UI language', () async {
    final local = MemoryLanguageDataSource();
    final controller = LanguageController(
      repository: LanguageRepository(
        local: local,
        remote: FakeUserSettingsRepository(throwOnSave: true),
      ),
      deviceLocale: const Locale('en'),
    );
    await controller.load();
    await controller.attachUser('u3');
    await controller.setLanguage(AppLanguage.turkish);
    expect(controller.languageCode, 'tr');
    expect(await local.readLanguageCode(), 'tr');
  });

  test('offline language switch works before attachUser', () async {
    final local = MemoryLanguageDataSource();
    final controller = LanguageController(
      repository: LanguageRepository(local: local),
      deviceLocale: const Locale('en'),
    );
    await controller.load();
    await controller.setLanguage(AppLanguage.turkish);
    expect(controller.languageCode, 'tr');
    expect(await local.readLanguageCode(), 'tr');
  });
}
