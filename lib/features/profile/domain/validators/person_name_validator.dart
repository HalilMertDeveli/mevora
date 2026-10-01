enum PersonNameIssue { required, tooLong }

/// One rule for a member's first and last name, shared by onboarding and
/// Edit Profile and mirrored by `functions/src/personName.ts`.
///
/// Deliberately permissive: any script, accents, apostrophes, hyphens and
/// multi-part names pass. A name only has to contain a letter and fit the
/// length cap.
abstract final class PersonNameValidator {
  static const int maxFirstNameLength = 40;
  static const int maxLastNameLength = 50;

  static final _letter = RegExp(r'\p{L}', unicode: true);

  static String normalize(String? value) => (value ?? '').trim();

  static PersonNameIssue? validate(String? value, {required int maxLength}) {
    final name = normalize(value);
    if (!_letter.hasMatch(name)) {
      return PersonNameIssue.required;
    }
    if (name.length > maxLength) {
      return PersonNameIssue.tooLong;
    }
    return null;
  }

  static PersonNameIssue? validateFirstName(String? value) =>
      validate(value, maxLength: maxFirstNameLength);

  static PersonNameIssue? validateLastName(String? value) =>
      validate(value, maxLength: maxLastNameLength);

  /// The public first name to seed from a sign-in provider's full name
  /// ("Halil Develi" -> "Halil"). The rest of that name is never written to
  /// the public profile.
  static String? firstNameHint(String? providerName) {
    final name = normalize(providerName);
    if (name.isEmpty) {
      return null;
    }
    return name.split(RegExp(r'\s+')).first;
  }
}
