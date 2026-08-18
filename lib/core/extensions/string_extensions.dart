extension StringX on String {
  bool get isBlank => trim().isEmpty;

  String get trimmed => trim();

  String get initials {
    final parts = trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    if (parts.isEmpty) {
      return '';
    }
    final letters = parts.take(2).map((part) => part[0].toUpperCase());
    return letters.join();
  }
}
