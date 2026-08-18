enum AccountStatus { active, disabled, banned, deleted }

extension AccountStatusX on AccountStatus {
  String get firestoreValue => name;

  static AccountStatus fromFirestore(Object? value, {bool? legacyIsBanned, bool? legacyIsActive}) {
    if (value is String) {
      return AccountStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => AccountStatus.active,
      );
    }
    if (legacyIsBanned == true) {
      return AccountStatus.banned;
    }
    if (legacyIsActive == false) {
      return AccountStatus.disabled;
    }
    return AccountStatus.active;
  }

  bool get isBanned => this == AccountStatus.banned;

  bool get isActive => this == AccountStatus.active;
}
