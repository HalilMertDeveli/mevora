import 'package:mevora/features/settings/domain/entities/user_settings.dart';

abstract class UserSettingsRepository {
  Future<UserSettings> load(String uid);

  Future<void> save(UserSettings settings);

  Future<void> saveLanguageCode(String uid, String languageCode);
}
