import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/network/backend_callable.dart';

class FirebaseFunctionsCallable implements BackendCallable {
  FirebaseFunctionsCallable({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String region = 'europe-west1',
    Duration tokenRefreshTimeout = const Duration(seconds: 10),
    Duration callTimeout = const Duration(seconds: 60),
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: region),
       _auth = auth ?? FirebaseAuth.instance,
       _tokenRefreshTimeout = tokenRefreshTimeout,
       _callTimeout = callTimeout;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final Duration _tokenRefreshTimeout;
  final Duration _callTimeout;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    // 2nd gen callables return Unauthenticated if the ID token is missing
    // or stale after a long idle. Force-refresh so cold resume works, but
    // never let that refresh outlive its own deadline.
    await _refreshIdToken();
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: _callTimeout),
    );
    try {
      final result = await callable.call<dynamic>(data ?? <String, dynamic>{});
      return callablePayload(result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        await _refreshIdToken();
        final retry = await callable.call<dynamic>(
          data ?? <String, dynamic>{},
        );
        return callablePayload(retry.data);
      }
      rethrow;
    }
  }

  Future<void> _refreshIdToken() {
    final user = _auth.currentUser;
    if (user == null) {
      return Future<void>.value();
    }
    return refreshIdTokenWithDeadline(
      () => user.getIdToken(true),
      timeout: _tokenRefreshTimeout,
    );
  }
}

/// Best-effort ID token refresh.
///
/// `User.getIdToken(true)` is a network round trip with no deadline of its
/// own, so a stalled connection, a slow App Check attestation or an
/// unreachable auth backend can leave it pending indefinitely. Every callable
/// awaits it first, which would strand any UI on a spinner with no way out.
///
/// A stale token is not fatal: [BackendCallable] retries once when the
/// callable answers `unauthenticated`. A refresh that times out or fails is
/// therefore swallowed and the call proceeds with the cached token.
Future<void> refreshIdTokenWithDeadline(
  Future<Object?> Function() refresh, {
  required Duration timeout,
}) async {
  try {
    await refresh().timeout(timeout);
  } on Object {
    // Best effort — the callable surfaces a real auth failure on its own.
  }
}

/// Cloud Functions may return `Map<Object?, Object?>` with null values.
/// A typed `call<Map<String, dynamic>>` throws on those payloads.
Map<String, dynamic> callablePayload(Object? raw) {
  if (raw == null) {
    return <String, dynamic>{};
  }
  if (raw is Map) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }
  throw FormatException('Callable returned ${raw.runtimeType}');
}
