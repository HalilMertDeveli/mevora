/// Trusted backend surface. Widgets and controllers must not call SDKs.
abstract class BackendCallable {
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]);
}
