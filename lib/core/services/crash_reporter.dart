import 'package:flutter/foundation.dart';

/// Abstraction so crash reporting can be wired without putting Firebase
/// types inside the generic error handler.
abstract class CrashReporter {
  void recordFlutterFatal(FlutterErrorDetails details);

  bool recordUncaught(Object error, StackTrace stackTrace);
}
