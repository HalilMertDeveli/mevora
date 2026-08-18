import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for the user's language. Source of truth for fast startup.
abstract class LocalLanguageDataSource {
  Future<String?> readLanguageCode();

  Future<void> writeLanguageCode(String languageCode);
}

class SharedPreferencesLanguageDataSource implements LocalLanguageDataSource {
  SharedPreferencesLanguageDataSource({SharedPreferences? preferences})
    : _preferences = preferences;

  static const String key = 'mevora.languageCode';

  SharedPreferences? _preferences;

  Future<SharedPreferences> _store() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  @override
  Future<String?> readLanguageCode() async {
    final prefs = await _store();
    return prefs.getString(key);
  }

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    final prefs = await _store();
    await prefs.setString(key, languageCode);
  }
}

/// In-memory store for tests and environments without plugin bindings.
class MemoryLanguageDataSource implements LocalLanguageDataSource {
  MemoryLanguageDataSource({String? languageCode}) : _languageCode = languageCode;

  String? _languageCode;

  @override
  Future<String?> readLanguageCode() async => _languageCode;

  @override
  Future<void> writeLanguageCode(String languageCode) async {
    _languageCode = languageCode;
  }
}
