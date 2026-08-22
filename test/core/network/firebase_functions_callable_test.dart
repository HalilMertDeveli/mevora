import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';

void main() {
  test('callable payload keeps null fields without throwing', () {
    final payload = callablePayload({
      'answeredIds': ['rq_001'],
      'answerCount': 1,
      'offerCooldownUntil': null,
      'lastCompletedAt': null,
    });
    expect(payload['answeredIds'], ['rq_001']);
    expect(payload['answerCount'], 1);
    expect(payload['offerCooldownUntil'], isNull);
    expect(callablePayload(null), isEmpty);
  });
}
