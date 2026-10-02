/// What the auth layer found when asked whether the account behind a restored
/// session still exists, before anything is written for that session.
enum RestoredSessionCheck {
  /// Firebase Auth still has the account.
  accountExists,

  /// The session is over and this device no longer holds it: the account was
  /// deleted or disabled, its tokens were revoked, or it was signed out while
  /// the check ran.
  sessionClosed,

  /// Firebase Auth could not be asked (offline, timeout). Nothing was changed.
  unverified,
}
