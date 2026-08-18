import 'package:mevora/core/localization/app_language.dart';
import 'package:mevora/core/localization/local_language_data_source.dart';
import 'package:mevora/features/settings/domain/repositories/user_settings_repository.dart';

/// Resolves language with local storage as the fast source of truth.
/// Firebase [UserSettingsRepository] is best-effort sync after login.
class LanguageRepository {
  LanguageRepository({
    required LocalLanguageDataSource local,
    UserSettingsRepository? remote,
  }) : _local = local,
       _remote = remote;

  final LocalLanguageDataSource _local;
  final UserSettingsRepository? _remote;

  Future<AppLanguage?> loadSaved() async {
    final code = await _local.readLanguageCode();
    if (code == null || code.trim().isEmpty) {
      return null;
    }
    return AppLanguage.fromCode(code);
  }

  Future<void> saveLocal(AppLanguage language) {
    return _local.writeLanguageCode(language.code);
  }

  Future<void> syncToRemote({
    required String uid,
    required AppLanguage language,
  }) async {
    final remote = _remote;
    if (remote == null) {
      return;
    }
    await remote.saveLanguageCode(uid, language.code);
  }
}
