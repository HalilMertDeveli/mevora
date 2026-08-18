abstract final class Validators {
  static String? requiredField(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, field: 'Email');
    if (requiredError != null) {
      return requiredError;
    }
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(value!.trim())) {
      return 'Enter a valid email';
    }
    return null;
  }

  static String? minLength(
    String? value,
    int min, {
    String field = 'This field',
  }) {
    final requiredError = requiredField(value, field: field);
    if (requiredError != null) {
      return requiredError;
    }
    if (value!.trim().length < min) {
      return '$field must be at least $min characters';
    }
    return null;
  }
}
