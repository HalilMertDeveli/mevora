import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/music/data/datasources/music_data_source.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';
import 'package:mevora/features/music/domain/repositories/music_repository.dart';

class MusicRepositoryImpl implements MusicRepository {
  MusicRepositoryImpl({required MusicDataSource dataSource})
    : _dataSource = dataSource;

  final MusicDataSource _dataSource;

  @override
  Future<Result<MusicProfile>> getProfile() async {
    try {
      return Success(await _dataSource.getProfile());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<MusicProfile>> connectSpotify() async {
    try {
      return Success(await _dataSource.connectSpotify());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<void>> disconnectSpotify() async {
    try {
      await _dataSource.disconnectSpotify();
      return const Success(null);
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<MusicProfile>> syncTaste() async {
    try {
      return Success(await _dataSource.syncTaste());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<WeeklyMusicStats>> getWeeklyStats() async {
    try {
      return Success(await _dataSource.getWeeklyStats());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<List<SameTasteMatch>>> getSameTasteProfiles() async {
    try {
      return Success(await _dataSource.getSameTasteProfiles());
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<MatchMusicCompatibility>> getMatchMusicCompatibility(
    String matchId,
  ) async {
    try {
      return Success(await _dataSource.getMatchMusicCompatibility(matchId));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}
