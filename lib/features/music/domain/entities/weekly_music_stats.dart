import 'package:mevora/features/music/domain/entities/music_track.dart';

class WeeklyMusicStats {
  const WeeklyMusicStats({
    required this.weekId,
    this.tracks = const [],
  });

  /// ISO week id such as `2026-W34`.
  final String weekId;
  final List<WeeklyTrackStat> tracks;

  bool get isEmpty => tracks.isEmpty;

  static const empty = WeeklyMusicStats(weekId: '');
}

class WeeklyTrackStat {
  const WeeklyTrackStat({
    required this.track,
    required this.playCount,
  });

  final MusicTrack track;
  final int playCount;
}
