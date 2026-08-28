/// Debug counters for Humor Lab media controllers (stress / leak checks).
///
/// Not a security boundary — used in debug/tests only.
class HumorMediaControllerStats {
  HumorMediaControllerStats._();

  static int youtubeLive = 0;
  static int youtubePeak = 0;
  static int youtubeCreated = 0;
  static int youtubeDisposed = 0;

  static int videoLive = 0;
  static int videoPeak = 0;
  static int videoCreated = 0;
  static int videoDisposed = 0;

  static void reset() {
    youtubeLive = 0;
    youtubePeak = 0;
    youtubeCreated = 0;
    youtubeDisposed = 0;
    videoLive = 0;
    videoPeak = 0;
    videoCreated = 0;
    videoDisposed = 0;
  }

  static void onYoutubeCreated() {
    youtubeCreated += 1;
    youtubeLive += 1;
    if (youtubeLive > youtubePeak) {
      youtubePeak = youtubeLive;
    }
  }

  static void onYoutubeDisposed() {
    youtubeDisposed += 1;
    if (youtubeLive > 0) {
      youtubeLive -= 1;
    }
  }

  static void onVideoCreated() {
    videoCreated += 1;
    videoLive += 1;
    if (videoLive > videoPeak) {
      videoPeak = videoLive;
    }
  }

  static void onVideoDisposed() {
    videoDisposed += 1;
    if (videoLive > 0) {
      videoLive -= 1;
    }
  }

  static Map<String, int> snapshot() => {
        'youtubeLive': youtubeLive,
        'youtubePeak': youtubePeak,
        'youtubeCreated': youtubeCreated,
        'youtubeDisposed': youtubeDisposed,
        'videoLive': videoLive,
        'videoPeak': videoPeak,
        'videoCreated': videoCreated,
        'videoDisposed': videoDisposed,
      };
}
