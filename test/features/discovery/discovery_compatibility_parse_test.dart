import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_display_status.dart';
import 'package:mevora/features/discovery/data/repositories/discovery_repository_impl.dart';
import 'package:mevora/features/discovery/domain/entities/discovery_radius.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';

class _StringScoreBackend implements BackendCallable {
  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    return {
      'items': [
        {
          'uid': 'user-b',
          'compatibilityScore': '87',
          'profile': {
            'displayName': 'Ada',
            'age': 27,
            'interests': ['travel'],
          },
        },
      ],
    };
  }
}

void main() {
  test('firestoreInt parses numeric strings', () {
    expect(firestoreInt('72', 0), 72);
    expect(firestoreInt('87.4', 0), 87);
  });

  test('discovery repository parses string compatibility scores', () async {
    final repository = DiscoveryRepositoryImpl(backend: _StringScoreBackend());
    final page = await repository.getCandidates(radius: DiscoveryRadius.km25);
    expect(page, isA<Success<DiscoveryPageResult>>());
    final candidate = page.valueOrNull!.candidates.single;
    expect(candidate.compatibilityScore, 87);
    expect(candidate.compatibilityStatus, CompatibilityDisplayStatus.ready);
  });
}
