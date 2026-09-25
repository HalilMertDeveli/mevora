import 'package:mevora/features/music/domain/entities/match_music_compatibility.dart';
import 'package:mevora/features/music/domain/entities/music_taste.dart';
import 'package:mevora/features/music/domain/entities/public_music_profile.dart';
import 'package:mevora/features/music/domain/entities/same_taste_match.dart';
import 'package:mevora/features/music/domain/entities/weekly_music_stats.dart';

/// Remote music API. Implementations talk to Cloud Functions or in-memory mocks.
abstract class MusicDataSource {
  Future<MusicProfile> getProfile();

  Future<MusicProfile> connectSpotify();

  Future<void> disconnectSpotify();

  Future<MusicProfile> syncTaste();

  /// Publishes the owner's chosen artists and tracks. Identifiers only —
  /// the backend resolves names, artwork and links from their own import.
  Future<PublicMusicProfile> updatePublicMusicProfile({
    required bool enabled,
    required List<String> artistIds,
    required List<String> trackIds,
  });

  Future<WeeklyMusicStats> getWeeklyStats();

  Future<List<SameTasteMatch>> getSameTasteProfiles();

  Future<MatchMusicCompatibility> getMatchMusicCompatibility(String matchId);
}
