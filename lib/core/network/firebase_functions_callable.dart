import 'package:cloud_functions/cloud_functions.dart';
import 'package:mevora/core/network/backend_callable.dart';

class FirebaseFunctionsCallable implements BackendCallable {
  FirebaseFunctionsCallable({
    FirebaseFunctions? functions,
    String region = 'europe-west1',
  }) : _functions =
           functions ?? FirebaseFunctions.instanceFor(region: region);

  final FirebaseFunctions _functions;

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    final callable = _functions.httpsCallable(name);
    final result = await callable.call<Map<String, dynamic>>(data ?? const {});
    return Map<String, dynamic>.from(result.data);
  }
}
