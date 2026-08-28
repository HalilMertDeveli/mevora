import 'package:mevora/core/errors/failure.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_server_payload.dart';

/// Fetches match-scoped Why You Matched reasons from Cloud Functions.
class WhyYouMatchedRemoteDataSource {
  WhyYouMatchedRemoteDataSource({required BackendCallable backend})
      : _backend = backend;

  final BackendCallable _backend;

  static const callableName = 'getWhyYouMatched';

  Future<Result<WhyYouMatchedServerPayload>> fetchForMatch({
    required String matchId,
    bool forceRefresh = false,
  }) async {
    final id = matchId.trim();
    if (id.isEmpty) {
      return const Err(ValidationFailure('matchId required'));
    }
    try {
      final data = await _backend.invoke(callableName, {
        'matchId': id,
        if (forceRefresh) 'forceRefresh': true,
      });
      if (!_looksLikePayload(data)) {
        return const Err(ValidationFailure('invalid why-you-matched payload'));
      }
      final payload = WhyYouMatchedServerPayload.fromJson(data);
      return Success(payload);
    } catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  /// Rejects clearly malformed CF bodies without inventing reasons.
  static bool _looksLikePayload(Map<String, dynamic> data) {
    if (data.containsKey('available') && data['available'] is! bool) {
      return false;
    }
    if (data.containsKey('reasons') && data['reasons'] is! List) {
      return false;
    }
    if (data.containsKey('overallScore') &&
        data['overallScore'] != null &&
        data['overallScore'] is! num) {
      return false;
    }
    return true;
  }
}
