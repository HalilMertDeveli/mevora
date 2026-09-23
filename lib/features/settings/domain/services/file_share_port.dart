/// Outcome of handing a generated file to the platform share/save sheet.
enum FileShareOutcome {
  /// The user picked a target (share, save, send, open elsewhere).
  shared,

  /// The sheet opened and the user backed out without choosing a target.
  dismissed,

  /// No share mechanism is available on this platform.
  unavailable,
}

/// Hands a locally generated file to the platform's share/save sheet.
///
/// The data export lives in the app's private cache directory, which a user
/// cannot browse to. Delivery therefore has to go through the platform sheet;
/// this port keeps that plugin call out of widgets and out of the service, so
/// both stay testable.
abstract class FileSharePort {
  Future<FileShareOutcome> shareFile({
    required String path,
    required String mimeType,
    String? subject,
  });
}
