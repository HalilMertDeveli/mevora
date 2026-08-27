import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';

/// Remote music API. Implementations talk to Cloud Functions or in-memory mocks.
abstract class MusicDataSource {
  Future<MusicProfile> getProfile();

  Future<MusicProfile> connectSpotify();

  Future<void> disconnectSpotify();

  Future<MusicProfile> syncTaste();

  Future<WeeklyMusicStats> getWeeklyStats();

  Future<List<SameTasteMatch>> getSameTasteProfiles();

  Future<MatchMusicCompatibility> getMatchMusicCompatibility(String matchId);
}
