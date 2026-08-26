import 'package:mevora/features/profile/domain/entities/user_profile.dart';

abstract final class DiscoveryPrefsValidator {
  static const int minAllowedAge = 18;
  static const int maxAllowedAge = 99;
  static const int minDistance = 1;
  static const int maxDistance = 500;

  static String? validate(UserPreferences prefs) {
    if (prefs.minAge < minAllowedAge) {
      return 'min_age_invalid';
    }
    if (prefs.maxAge > maxAllowedAge) {
      return 'max_age_invalid';
    }
    if (prefs.maxAge < prefs.minAge) {
      return 'age_range_invalid';
    }
    if (prefs.maxDistance < minDistance || prefs.maxDistance > maxDistance) {
      return 'distance_invalid';
    }
    return null;
  }
}
