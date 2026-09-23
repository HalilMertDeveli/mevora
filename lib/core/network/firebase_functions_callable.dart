import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/network/backend_callable.dart';

class FirebaseFunctionsCallable implements BackendCallable {
  FirebaseFunctionsCallable({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String region = 'europe-west1',
    this.refreshDeadline = const Duration(seconds: 10),
    this.callTimeout = const Duration(seconds: 60),
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: region),
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  /// Upper bound on the forced ID-token refresh that precedes every call.
  final Duration refreshDeadline;

  /// Upper bound on the callable itself.
  final Duration callTimeout;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    // 2nd gen callables return Unauthenticated if the ID token is missing
    // or stale after a long idle. Force-refresh so cold resume works.
    await refreshIdTokenWithDeadline(
      _auth.currentUser?.getIdToken(true),
      deadline: refreshDeadline,
    );
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: callTimeout),
    );
    try {
      final result = await callable.call<dynamic>(data ?? <String, dynamic>{});
      return callablePayload(result.data);
    } on FirebaseFunctionsException catch (error) {
      if (error.code == 'unauthenticated') {
        await refreshIdTokenWithDeadline(
          _auth.currentUser?.getIdToken(true),
          deadline: refreshDeadline,
        );
        final retry = await callable.call<dynamic>(
          data ?? <String, dynamic>{},
        );
        return callablePayload(retry.data);
      }
      rethrow;
    }
  }
}

/// Bounds the forced ID-token refresh that precedes a callable.
///
/// The refresh is a network round trip with no deadline of its own, so a
/// stalled connection, an unreachable auth backend or a slow App Check
/// attestation used to leave it pending forever — the caller hung with
/// nothing thrown and nothing logged. A stale token is survivable instead:
/// the callable already retries once on `unauthenticated`. An unbounded wait
/// is not, so a timed-out or failed refresh is swallowed and the call
/// proceeds with whatever token is on hand.
Future<void> refreshIdTokenWithDeadline(
  Future<Object?>? refresh, {
  required Duration deadline,
}) async {
  if (refresh == null) {
    return;
  }
  try {
    await refresh.timeout(deadline);
  } on Object {
    // Deliberately ignored — see above.
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
