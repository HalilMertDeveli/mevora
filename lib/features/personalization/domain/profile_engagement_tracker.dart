/// Collects one profile visit's weak engagement signals for adaptive
/// personalization: whether details were opened, how many photos were seen,
/// whether the music and "why you're seeing this" sections came into view, and
/// how long the profile was on screen WHILE the app was in the foreground.
///
/// Nothing else is recorded: no scroll positions, no timestamps per action,
/// nothing about the content. The server clamps and buckets these again and
/// counts at most one visit per person per day, so a rebuild, a quick reopen
/// or leaving the phone on the table cannot farm anything.
class ProfileEngagementTracker {
  ProfileEngagementTracker({required this.candidateUid, Stopwatch? stopwatch})
    : _dwell = stopwatch ?? Stopwatch();

  final String candidateUid;
  final Stopwatch _dwell;
  final Set<int> _photosSeen = {0};
  bool _spotifyOpened = false;
  bool _whyOpened = false;
  bool _finished = false;
  bool _foreground = true;

  bool get isFinished => _finished;

  void start() {
    if (_finished || !_foreground) return;
    _dwell.start();
  }

  /// App went to the background (or the screen was covered): stop the clock.
  void pause() {
    _foreground = false;
    _dwell.stop();
  }

  void resume() {
    _foreground = true;
    if (!_finished) _dwell.start();
  }

  void photoViewed(int index) {
    if (index >= 0) _photosSeen.add(index);
  }

  void spotifySectionSeen() => _spotifyOpened = true;

  void whyThisPersonSeen() => _whyOpened = true;

  /// The payload for `recordProfileEngagement`, exactly once per visit.
  Map<String, Object>? finish() {
    if (_finished) return null;
    _finished = true;
    _dwell.stop();
    return {
      'candidateUid': candidateUid,
      'detailsOpened': true,
      'photosViewed': _photosSeen.length,
      'spotifyOpened': _spotifyOpened,
      'whyThisPersonOpened': _whyOpened,
      'dwellMs': _dwell.elapsedMilliseconds,
    };
  }
}
