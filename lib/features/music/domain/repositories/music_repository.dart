import 'package:mevora/core/errors/result.dart';
import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';

abstract class MusicRepository {
  Future<Result<MusicProfile>> getProfile();

  Future<Result<MusicProfile>> connectSpotify();

  Future<Result<void>> disconnectSpotify();

  Future<Result<MusicProfile>> syncTaste();

  Future<Result<WeeklyMusicStats>> getWeeklyStats();

  Future<Result<List<SameTasteMatch>>> getSameTasteProfiles();

  Future<Result<MatchMusicCompatibility>> getMatchMusicCompatibility(
    String matchId,
  );
}
