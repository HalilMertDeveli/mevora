import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_server_payload.dart';

/// Match-scoped Why You Matched reasons from Cloud Functions.
abstract class WhyYouMatchedRepository {
  Future<Result<WhyYouMatchedServerPayload>> fetchForMatch({
    required String matchId,
    bool forceRefresh = false,
  });
}
