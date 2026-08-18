import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/features/settings/data/datasources/firebase_settings_data_source.dart';
import 'package:mevora/features/settings/domain/entities/user_settings.dart';
import 'package:mevora/features/settings/domain/repositories/user_settings_repository.dart';

class UserSettingsRepositoryImpl implements UserSettingsRepository {
  UserSettingsRepositoryImpl({required FirebaseSettingsDataSource dataSource})
    : _dataSource = dataSource;

  final FirebaseSettingsDataSource _dataSource;

  @override
  Future<UserSettings> load(String uid) {
    return _dataSource.loadSettings(uid);
  }

  @override
  Future<void> save(UserSettings settings) {
    return _dataSource.saveSettings(settings);
  }

  @override
  Future<void> saveLanguageCode(String uid, String languageCode) async {
    final current = await _dataSource.loadSettings(uid);
    final normalized = AppLanguage.fromCode(languageCode).code;
    await _dataSource.saveSettings(
      current.copyWith(uid: uid, languageCode: normalized),
    );
  }
}
