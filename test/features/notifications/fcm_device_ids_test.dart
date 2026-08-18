import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/notifications/data/datasources/firebase_messaging_data_source.dart';

void main() {
  test('device ids are stable, path-safe, and bounded', () {
    const token = 'abc:APA91bVeryLongTokenValueWith/slash.and.dots';
    final id = FcmDeviceIds.fromToken(token);
    expect(id.contains('/'), isFalse);
    expect(id.contains('.'), isFalse);
    expect(FcmDeviceIds.fromToken(token), id);
    expect(id.length, lessThanOrEqualTo(128));
  });
}
