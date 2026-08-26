/// Validates password change input. Passwords live in Firebase Auth only.
abstract final class PasswordValidator {
  static const int minLength = 8;

  static String? validateCurrent(String? value) {
    if (value == null || value.isEmpty) {
      return 'current_password_required';
    }
    return null;
  }

  static String? validateNew(String? value) {
    if (value == null || value.isEmpty) {
      return 'new_password_required';
    }
    if (value.length < minLength) {
      return 'password_too_short';
    }
    return null;
  }

  static String? validateConfirm(String? newPassword, String? confirm) {
    if (confirm == null || confirm.isEmpty) {
      return 'confirm_password_required';
    }
    if (newPassword != confirm) {
      return 'passwords_do_not_match';
    }
    return null;
  }

  static bool isValidChange({
    required String current,
    required String newPassword,
    required String confirm,
  }) {
    return validateCurrent(current) == null &&
        validateNew(newPassword) == null &&
        validateConfirm(newPassword, confirm) == null;
  }
}
