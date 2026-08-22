import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mevora/core/network/backend_callable.dart';

class FirebaseFunctionsCallable implements BackendCallable {
  FirebaseFunctionsCallable({
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    String region = 'europe-west1',
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: region),
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    // 2nd gen callables return Unauthenticated if the ID token is missing.
    await _auth.currentUser?.getIdToken();
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    final result = await callable.call<dynamic>(data ?? <String, dynamic>{});
    return callablePayload(result.data);
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
