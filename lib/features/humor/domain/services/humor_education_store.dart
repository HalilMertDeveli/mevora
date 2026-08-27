import 'package:shared_preferences/shared_preferences.dart';

/// Per-user Humor Lab education flags (device-local, uid-scoped).
/// Survives logout/login for the same uid on this device.
class HumorEducationStore {
  HumorEducationStore({SharedPreferences? preferences})
      : _preferences = preferences;

  SharedPreferences? _preferences;

  static String _key(String uid, String name) => 'mevora.humor.$name.$uid';

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Future<bool> isIntroSeen(String uid) async {
    if (uid.isEmpty) return true;
    final p = await _prefs();
    return p.getBool(_key(uid, 'introSeen')) ?? false;
  }

  Future<void> markIntroSeen(String uid) async {
    if (uid.isEmpty) return;
    final p = await _prefs();
    await p.setBool(_key(uid, 'introSeen'), true);
  }

  Future<bool> isRatingHelpDismissed(String uid) async {
    if (uid.isEmpty) return false;
    final p = await _prefs();
    return p.getBool(_key(uid, 'ratingHelpDismissed')) ?? false;
  }

  Future<void> markRatingHelpDismissed(String uid) async {
    if (uid.isEmpty) return;
    final p = await _prefs();
    await p.setBool(_key(uid, 'ratingHelpDismissed'), true);
  }

  Future<bool> isAdInfoSeen(String uid) async {
    if (uid.isEmpty) return true;
    final p = await _prefs();
    return p.getBool(_key(uid, 'adInfoSeen')) ?? false;
  }

  Future<void> markAdInfoSeen(String uid) async {
    if (uid.isEmpty) return;
    final p = await _prefs();
    await p.setBool(_key(uid, 'adInfoSeen'), true);
  }

  Future<bool> wasMilestoneShown(String uid, int milestone) async {
    if (uid.isEmpty) return true;
    final p = await _prefs();
    return p.getBool(_key(uid, 'milestone_$milestone')) ?? false;
  }

  Future<void> markMilestoneShown(String uid, int milestone) async {
    if (uid.isEmpty) return;
    final p = await _prefs();
    await p.setBool(_key(uid, 'milestone_$milestone'), true);
  }

  /// Test helper.
  Future<void> clearForUser(String uid) async {
    if (uid.isEmpty) return;
    final p = await _prefs();
    for (final name in [
      'introSeen',
      'ratingHelpDismissed',
      'adInfoSeen',
      'milestone_1',
      'milestone_5',
      'milestone_10',
      'milestone_12',
      'milestone_15',
      'milestone_20',
    ]) {
      await p.remove(_key(uid, name));
    }
  }
}
