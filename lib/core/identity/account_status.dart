enum AccountStatus { active, disabled, suspended, banned, deleted }

extension AccountStatusX on AccountStatus {
  String get firestoreValue => name;

  /// Reads `users/{uid}` the way the backend does (effectiveAccountStatus in
  /// functions/src/profileSafety.ts): the canonical `accountStatus` string,
  /// with the legacy `isBanned` / `isSuspended` flags still restricting on
  /// their own. A suspension whose `suspendedUntil` has passed is over.
  static AccountStatus fromFirestore(
    Object? value, {
    bool? legacyIsBanned,
    bool? legacyIsActive,
    bool? legacyIsSuspended,
    DateTime? suspendedUntil,
    DateTime? now,
  }) {
    if (value == AccountStatus.deleted.name) {
      return AccountStatus.deleted;
    }
    if (value == AccountStatus.banned.name || legacyIsBanned == true) {
      return AccountStatus.banned;
    }
    if (value == AccountStatus.suspended.name || legacyIsSuspended == true) {
      final until = suspendedUntil;
      if (until != null && !until.isAfter(now ?? DateTime.now())) {
        return AccountStatus.active;
      }
      return AccountStatus.suspended;
    }
    if (value is String) {
      return AccountStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => AccountStatus.active,
      );
    }
    if (legacyIsActive == false) {
      return AccountStatus.disabled;
    }
    return AccountStatus.active;
  }

  bool get isBanned => this == AccountStatus.banned;

  bool get isSuspended => this == AccountStatus.suspended;

  bool get isActive => this == AccountStatus.active;
}
