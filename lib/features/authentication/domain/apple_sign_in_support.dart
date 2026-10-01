import 'package:flutter/foundation.dart';

/// Whether Sign in with Apple can run on this device.
///
/// It is implemented for Apple platforms only. The option is offered only
/// where this is true: a button that can never succeed must not be shown.
bool get isAppleSignInSupported {
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}
