import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_remote_data_source.dart';
import 'package:mevora/features/compatibility/data/why_you_matched/why_you_matched_server_payload.dart';
import 'package:mevora/features/compatibility/domain/repositories/why_you_matched_repository.dart';

class WhyYouMatchedRepositoryImpl implements WhyYouMatchedRepository {
  WhyYouMatchedRepositoryImpl({required WhyYouMatchedRemoteDataSource remote})
      : _remote = remote;

  final WhyYouMatchedRemoteDataSource _remote;

  @override
  Future<Result<WhyYouMatchedServerPayload>> fetchForMatch({
    required String matchId,
    bool forceRefresh = false,
  }) {
    return _remote.fetchForMatch(
      matchId: matchId,
      forceRefresh: forceRefresh,
    );
  }
}
