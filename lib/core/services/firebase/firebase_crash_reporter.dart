import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:mevora/core/services/crash_reporter.dart';

class FirebaseCrashReporter implements CrashReporter {
  const FirebaseCrashReporter();

  @override
  void recordFlutterFatal(FlutterErrorDetails details) {
    unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
  }

  @override
  bool recordUncaught(Object error, StackTrace stackTrace) {
    if (_isOptionalAssetFailure(error)) {
      return true;
    }
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true),
    );
    return true;
  }

  static bool _isOptionalAssetFailure(Object error) {
    final message = error.toString();
    return message.contains('RiveFileLoaderException') ||
        message.contains('Unable to load asset: "assets/rive/') ||
        // Firestore MethodChannel race on cancelled transactions (non-fatal).
        message.contains('Future already completed') ||
        (message.contains('MissingPluginException') &&
            message.contains('firebase_firestore/transaction')) ||
        message.contains('permission-denied') ||
        message.contains('PERMISSION_DENIED');
  }
}
