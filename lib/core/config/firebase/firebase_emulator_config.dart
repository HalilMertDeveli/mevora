/// Local Firebase Emulator Suite host and ports.
///
/// Development targets Firestore / Functions / Storage emulators so it never
/// touches staging or production data. Auth emulator is opt-in via
/// `--dart-define=USE_AUTH_EMULATOR=true` because it cannot send real SMS.
class FirebaseEmulatorConfig {
  const FirebaseEmulatorConfig({
    required this.host,
    this.authPort = 9099,
    this.firestorePort = 8080,
    this.functionsPort = 5001,
    this.storagePort = 9199,
  });

  final String host;
  final int authPort;
  final int firestorePort;
  final int functionsPort;
  final int storagePort;
}
