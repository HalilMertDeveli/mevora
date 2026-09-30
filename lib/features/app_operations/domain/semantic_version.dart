/// A release version as the stores and `pubspec.yaml` spell it: `x.y.z`.
///
/// Parsing is deliberately forgiving about the build suffix (`1.2.3+4` is
/// `1.2.3`) and strict about everything else. A value that cannot be read is
/// not a version at all — callers treat it as "no gate", never as "blocked".
class SemanticVersion implements Comparable<SemanticVersion> {
  const SemanticVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  /// `1`, `1.2` and `1.2.3` are accepted (missing parts are zero); a build
  /// suffix after `+` is ignored. Anything else — a pre-release tag, a fourth
  /// component, a negative or non-numeric part — returns null.
  static SemanticVersion? tryParse(Object? raw) {
    if (raw is! String) {
      return null;
    }
    var text = raw.trim();
    final plus = text.indexOf('+');
    if (plus >= 0) {
      text = text.substring(0, plus);
    }
    if (text.isEmpty) {
      return null;
    }
    final parts = text.split('.');
    if (parts.length > 3) {
      return null;
    }
    final numbers = <int>[];
    for (final part in parts) {
      if (part.isEmpty || !_digits.hasMatch(part)) {
        return null;
      }
      final value = int.tryParse(part);
      if (value == null) {
        return null;
      }
      numbers.add(value);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return SemanticVersion(numbers[0], numbers[1], numbers[2]);
  }

  static final RegExp _digits = RegExp(r'^\d{1,9}$');

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    return patch.compareTo(other.patch);
  }

  bool operator <(SemanticVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is SemanticVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
