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
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true),
    );
    return true;
  }
}
