import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:video_player/video_player.dart';

/// Builds the controller for one humor clip. Injectable so tests can drive
/// initialisation without a platform video player.
typedef HumorVideoControllerFactory = VideoPlayerController Function(Uri uri);

/// Why one attempt at playing a clip was abandoned. [value] is the analytics
/// and diagnostics spelling.
enum HumorMediaFailure {
  /// `initialize()` did not finish within [HumorContentPlayer.videoInitTimeout].
  timeout('timeout'),

  /// Initialised, but playback made no progress for
  /// [HumorContentPlayer.playbackStallTimeout] while it should have played.
  stall('stall'),

  /// The platform player (or the URL) failed.
  error('error'),

  /// Initialised with no frame size — it would paint nothing at all.
  zeroSize('zero_size');

  const HumorMediaFailure(this.value);

  final String value;
}

/// Full-bleed humor media: video (autoplay/mute/loop), image/meme, or a text
/// card.
///
/// An image or meme — including a GIPHY GIF, which the backend stores as an
/// animated WebP/GIF — goes through Flutter's own image pipeline, which
/// decodes and loops animated images itself; no video player is involved.
/// Its still poster shows while it loads, the first frame is bounded by
/// [imageLoadTimeout], and a failure gets "Try again" (once) and "Next".
///
/// A clip runs through an explicit state machine:
///
/// ```text
/// loading ──ready──▶ ready (playing while active and in the foreground,
///    ▲                 │    paused otherwise)
///    │ one silent      │ timeout / stall / error / zero size
///    │ auto retry      ▼
///    └──────────── attempt failed ──budget spent──▶ failed
///                                                 (Try again once / Next)
/// ```
///
/// Nothing is ever an endless spinner or a frozen frame: initialisation is
/// bounded by [videoInitTimeout], and while an initialised clip should be
/// playing a watchdog treats [playbackStallTimeout] without the position
/// moving as a stall. Every failure gets one fresh controller silently; the
/// next one lands in the failed state, whose "Try again" resets that budget
/// exactly once. So one card appearance downloads a clip at most twice on
/// its own, and at most twice more when the user asks for it.
class HumorContentPlayer extends StatefulWidget {
  const HumorContentPlayer({
    super.key,
    required this.content,
    this.isActive = true,
    this.replayToken = 0,
    this.onMediaError,
    this.onSkipUnplayable,
    this.analytics,
    this.videoControllerFactory,
  });

  /// How long a video may take to initialise before it counts as broken.
  static const videoInitTimeout = Duration(seconds: 12);

  /// How long an initialised clip that should be playing may go without its
  /// position advancing (buffering included) before it counts as stalled.
  static const playbackStallTimeout = Duration(seconds: 8);

  /// How long an image (an animated GIPHY WebP/GIF included) may take to show
  /// its first frame before it counts as broken.
  static const imageLoadTimeout = Duration(seconds: 15);

  /// Pause before the one silent retry, so a transient drop can clear.
  static const autoRetryDelay = Duration(milliseconds: 600);

  /// Downloads per budget: the first attempt plus one silent retry.
  static const attemptsPerBudget = 2;

  /// How often "Try again" may reset the budget per card appearance.
  static const maxManualRetries = 1;

  final HumorContent content;

  /// Only the active card plays; every other card is kept paused.
  final bool isActive;

  /// A change replays the active card's video from the start. Ignored while
  /// the card is not active, so an off-screen card never reloads anything.
  final int replayToken;

  /// Called once per item, with its contentId, when its media cannot be shown
  /// (for a clip: once its silent retry has failed too).
  final ValueChanged<String>? onMediaError;

  /// "Next" on a card whose media failed. Without it no "Next" is offered.
  final ValueChanged<String>? onSkipUnplayable;

  /// Receives `humor_media_failed` / `humor_media_retry`. Optional.
  final AnalyticsProvider? analytics;

  /// Defaults to [VideoPlayerController.networkUrl].
  final HumorVideoControllerFactory? videoControllerFactory;

  /// Whether [content] is played as a clip (by type, or an .mp4 URL).
  static bool isVideoContent(HumorContent content) {
    if (content.type == HumorContentType.video) {
      return true;
    }
    final url = content.downloadUrl;
    if (url == null || url.isEmpty) {
      return false;
    }
    final lower = url.toLowerCase();
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return lower.endsWith('.mp4') ||
        path.endsWith('.mp4') ||
        lower.contains('video/mp4');
  }

  /// The still this player shows first for [content]: a clip's poster (never
  /// the clip itself), an image's picture, nothing for a text card. Used to
  /// warm the image cache for upcoming cards.
  static String? stillUrlFor(HumorContent content) {
    if (isVideoContent(content)) {
      return content.thumbUrl;
    }
    final download = content.downloadUrl;
    if (download != null && download.isNotEmpty) {
      return download;
    }
    return content.thumbUrl;
  }

  @override
  State<HumorContentPlayer> createState() => _HumorContentPlayerState();
}

enum _VideoPhase { loading, ready, failed }

class _HumorContentPlayerState extends State<HumorContentPlayer>
    with WidgetsBindingObserver {
  /// Media at least this wide relative to its height (landscape, square or
  /// only slightly tall) is letterboxed on black so nothing is cropped; only
  /// clearly portrait media fills the card.
  static const _letterboxMinAspectRatio = 0.8;

  VideoPlayerController? _video;
  _VideoLoad? _load;
  Timer? _retryTimer;
  Timer? _watchdog;
  Duration? _lastPosition;

  /// Bumped whenever the card's media is torn down, so a load, retry or
  /// watchdog that fires late can tell it no longer belongs to this card.
  var _generation = 0;
  var _phase = _VideoPhase.loading;

  /// 1-based attempt within the current budget.
  var _attempt = 1;
  var _manualRetries = 0;
  var _muted = true;
  var _errorReported = false;
  var _appVisible = true;

  /// Image media: bounds the wait for the first frame.
  Timer? _imageTimer;

  /// Image media: the first frame is on screen (the timeout no longer applies).
  var _imageShown = false;

  /// Image media: the first frame did not arrive within the timeout.
  var _imageTimedOut = false;

  /// Image media: bumped by "Try again" so a fresh [Image] loads it anew.
  var _imageLoad = 0;

  /// Image media: why it failed, for the one failure report.
  var _imageFailure = HumorMediaFailure.error;

  /// True inside initState/didUpdateWidget, where a build follows anyway and
  /// setState must not be called.
  var _inSetup = false;

  bool get _isVideo => HumorContentPlayer.isVideoContent(widget.content);

  Uri? get _playableUri {
    final url = widget.content.downloadUrl;
    return MevoraNetworkImages.isHttpUrl(url) ? Uri.tryParse(url!) : null;
  }

  bool get _shouldPlay => widget.isActive && _appVisible;

  bool get _canRetryManually =>
      _playableUri != null &&
      _manualRetries < HumorContentPlayer.maxManualRetries;

  String? get _caption =>
      widget.content.hasText ? widget.content.textBody : null;

  @override
  void initState() {
    super.initState();
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final lifecycle = binding.lifecycleState;
    _appVisible = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _setup(_startMedia);
  }

  @override
  void didUpdateWidget(covariant HumorContentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.content;
    final next = widget.content;
    _setup(() {
      if (previous.contentId != next.contentId ||
          previous.downloadUrl != next.downloadUrl ||
          previous.type != next.type) {
        _resetMedia();
        _startMedia();
        return;
      }
      if (oldWidget.isActive != widget.isActive) {
        _syncPlayback();
      }
      if (oldWidget.replayToken != widget.replayToken && widget.isActive) {
        _replay();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final visible = state == AppLifecycleState.resumed;
    if (visible == _appVisible) {
      return;
    }
    _appVisible = visible;
    _syncPlayback();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resetMedia();
    super.dispose();
  }

  void _setup(VoidCallback body) {
    _inSetup = true;
    try {
      body();
    } finally {
      _inSetup = false;
    }
  }

  /// setState that is safe from anywhere: a no-op once disposed, and plain
  /// assignment inside initState/didUpdateWidget.
  void _update(VoidCallback change) {
    if (!mounted) {
      return;
    }
    if (_inSetup) {
      change();
    } else {
      setState(change);
    }
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

  void _startMedia() {
    if (!_isVideo) {
      _startImageTimer();
      return;
    }
    _phase = _VideoPhase.loading;
    _attempt = 1;
    _startAttempt();
  }

  /// The URL an image card draws: its media, else its still.
  String? get _imageUrl {
    final download = widget.content.downloadUrl;
    return download != null && download.isNotEmpty
        ? download
        : widget.content.thumbUrl;
  }

  /// Arms the first-frame timeout for an image card, so a load that never
  /// answers ends in the failed state instead of a blank card forever.
  void _startImageTimer() {
    _imageTimer?.cancel();
    _imageTimer = null;
    if (MevoraNetworkImages.provider(_imageUrl) == null) {
      return;
    }
    final generation = _generation;
    _imageTimer = Timer(HumorContentPlayer.imageLoadTimeout, () {
      _imageTimer = null;
      if (!_isCurrent(generation) || _imageShown || _imageTimedOut) {
        return;
      }
      _imageFailure = HumorMediaFailure.timeout;
      _update(() => _imageTimedOut = true);
      _reportMediaError();
    });
  }

  /// Called from the image's frame builder: the picture is on screen.
  void _onImageShown() {
    if (_imageShown) {
      return;
    }
    _imageShown = true;
    _imageTimer?.cancel();
    _imageTimer = null;
  }

  /// Called from the image's error builder: the load is over, badly.
  void _onImageError() {
    _imageTimer?.cancel();
    _imageTimer = null;
    _reportMediaError();
  }

  void _retryImage() {
    if (!_canRetryManually) {
      return;
    }
    _manualRetries += 1;
    _logRetry('manual');
    final image = MevoraNetworkImages.provider(_imageUrl);
    if (image != null) {
      // Drop whatever the cache holds (a pending or failed load) so the
      // retry really fetches again.
      unawaited(image.evict().then<void>((_) {}, onError: (Object _) {}));
    }
    setState(() {
      _imageTimedOut = false;
      _imageShown = false;
      _imageFailure = HumorMediaFailure.error;
      _imageLoad += 1;
    });
    _startImageTimer();
  }

  /// One download of the clip with a fresh controller.
  void _startAttempt() {
    final uri = _playableUri;
    if (uri == null) {
      // Nothing to (re)try: no playable URL is not a transient failure.
      _logFailure(HumorMediaFailure.error);
      _enterFailed();
      return;
    }
    VideoPlayerController controller;
    try {
      final factory =
          widget.videoControllerFactory ?? VideoPlayerController.networkUrl;
      controller = factory(uri);
    } catch (_) {
      _onAttemptFailed(HumorMediaFailure.error, _generation);
      return;
    }
    unawaited(_initVideo(controller, _generation));
  }

  Future<void> _initVideo(
    VideoPlayerController controller,
    int generation,
  ) async {
    final load = _VideoLoad(controller);
    _load = load;
    try {
      await load.initialize(HumorContentPlayer.videoInitTimeout);
      final value = controller.value;
      if (!value.isInitialized ||
          value.size.width <= 0 ||
          value.size.height <= 0) {
        throw const _ZeroSizeVideo();
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!_isCurrent(generation)) {
        unawaited(_disposeQuietly(controller));
        return;
      }
      controller.addListener(_onVideoValue);
      _lastPosition = controller.value.position;
      _update(() {
        _video = controller;
        _phase = _VideoPhase.ready;
      });
      _syncPlayback();
    } catch (error) {
      // Never wait on the dispose first: a stalled platform player may not
      // release promptly, and the card must leave the spinner now.
      unawaited(_disposeQuietly(controller));
      _onAttemptFailed(switch (error) {
        TimeoutException() => HumorMediaFailure.timeout,
        _ZeroSizeVideo() => HumorMediaFailure.zeroSize,
        _ => HumorMediaFailure.error,
      }, generation);
    } finally {
      if (identical(_load, load)) {
        _load = null;
      }
    }
  }

  /// Watches the bound clip: an error after it started fails the attempt,
  /// and every position change proves playback is alive.
  void _onVideoValue() {
    final video = _video;
    if (video == null) {
      return;
    }
    final value = video.value;
    if (value.hasError) {
      video.removeListener(_onVideoValue);
      _video = null;
      // Not from inside the controller's own notification.
      scheduleMicrotask(() => unawaited(_disposeQuietly(video)));
      _onAttemptFailed(HumorMediaFailure.error, _generation);
      return;
    }
    if (value.position != _lastPosition) {
      _lastPosition = value.position;
      if (_watchdog != null) {
        _armWatchdog();
      }
    }
  }

  /// One attempt is over: retry silently once, otherwise show the failure.
  void _onAttemptFailed(HumorMediaFailure reason, int generation) {
    if (!_isCurrent(generation)) {
      return;
    }
    _logFailure(reason);
    _teardownVideo();
    if (_attempt < HumorContentPlayer.attemptsPerBudget) {
      _attempt += 1;
      _logRetry('auto');
      _update(() => _phase = _VideoPhase.loading);
      final retryGeneration = _generation;
      _retryTimer = Timer(HumorContentPlayer.autoRetryDelay, () {
        _retryTimer = null;
        if (_isCurrent(retryGeneration)) {
          _startAttempt();
        }
      });
      return;
    }
    _enterFailed();
  }

  void _enterFailed() {
    _update(() => _phase = _VideoPhase.failed);
    _reportMediaError();
  }

  void _retryManually() {
    if (_phase != _VideoPhase.failed || !_canRetryManually) {
      return;
    }
    _manualRetries += 1;
    _logRetry('manual');
    _teardownVideo();
    _attempt = 1;
    setState(() => _phase = _VideoPhase.loading);
    _startAttempt();
  }

  void _skipUnplayable() {
    widget.onSkipUnplayable?.call(widget.content.contentId);
  }

  /// Releases the clip this card holds (bound or still loading) and every
  /// timer tied to it, and invalidates anything still in flight.
  void _teardownVideo() {
    _generation++;
    _retryTimer?.cancel();
    _retryTimer = null;
    _imageTimer?.cancel();
    _imageTimer = null;
    _stopWatchdog();
    _load?.cancel();
    _load = null;
    _lastPosition = null;
    final video = _video;
    _video = null;
    if (video != null) {
      video.removeListener(_onVideoValue);
      unawaited(_disposeQuietly(video));
    }
  }

  /// Drops whatever media this card holds and forgets its failure budget.
  void _resetMedia() {
    _teardownVideo();
    _phase = _VideoPhase.loading;
    _attempt = 1;
    _manualRetries = 0;
    _errorReported = false;
    _imageShown = false;
    _imageTimedOut = false;
    _imageFailure = HumorMediaFailure.error;
  }

  /// Tells [HumorContentPlayer.onMediaError] once per item, after the frame,
  /// so a listener may safely rebuild its own state.
  void _reportMediaError() {
    if (_errorReported) {
      return;
    }
    _errorReported = true;
    if (!_isVideo) {
      _logFailure(_imageFailure);
    }
    final generation = _generation;
    final contentId = widget.content.contentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent(generation)) {
        widget.onMediaError?.call(contentId);
      }
    });
  }

  void _logFailure(HumorMediaFailure reason) {
    final contentId = widget.content.contentId;
    final attempt = _isVideo ? _attempt : 1;
    if (!kReleaseMode) {
      debugPrint('[HUMOR-MEDIA] $contentId ${reason.value} attempt=$attempt');
    }
    _log(AnalyticsEvents.humorMediaFailed, {
      'content_id': contentId,
      'media': _isVideo ? 'video' : 'image',
      'reason': reason.value,
      'attempt': attempt,
    });
  }

  void _logRetry(String kind) {
    _log(AnalyticsEvents.humorMediaRetry, {
      'content_id': widget.content.contentId,
      'kind': kind,
    });
  }

  void _log(String name, Map<String, Object> parameters) {
    final analytics = widget.analytics;
    if (analytics == null) {
      return;
    }
    unawaited(_quietly(() => analytics.logEvent(name, parameters: parameters)));
  }

  /// Plays the bound clip only while it is the active card and the app is in
  /// the foreground; the stall watchdog runs exactly while it plays.
  void _syncPlayback() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      _stopWatchdog();
      return;
    }
    if (_shouldPlay) {
      unawaited(_quietly(video.play));
      _armWatchdog();
    } else {
      _stopWatchdog();
      unawaited(_quietly(video.pause));
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    final generation = _generation;
    _watchdog = Timer(HumorContentPlayer.playbackStallTimeout, () {
      _watchdog = null;
      if (!_isCurrent(generation) || _video == null || !_shouldPlay) {
        return;
      }
      _onAttemptFailed(HumorMediaFailure.stall, generation);
    });
  }

  void _stopWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Replays the already-loaded clip instead of downloading it again.
  void _replay() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return;
    }
    unawaited(
      _quietly(() async {
        await video.seekTo(Duration.zero);
        if (mounted && identical(_video, video) && _shouldPlay) {
          await video.play();
          _armWatchdog();
        }
      }),
    );
  }

  Future<void> _toggleMute() async {
    final video = _video;
    if (video == null) {
      return;
    }
    final next = !_muted;
    try {
      await video.setVolume(next ? 0 : 1);
    } catch (_) {
      return;
    }
    if (mounted) {
      setState(() => _muted = next);
    }
  }

  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Playback commands on a failing player are best-effort; a real
      // failure surfaces through the controller value instead.
    }
  }

  static Future<void> _disposeQuietly(VideoPlayerController controller) {
    return _quietly(controller.dispose);
  }

  static BoxFit _fitFor(double? aspectRatio) {
    if (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0) {
      return BoxFit.contain;
    }
    return aspectRatio < _letterboxMinAspectRatio
        ? BoxFit.cover
        : BoxFit.contain;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final content = widget.content;
    final isVideo = _isVideo;
    final caption = _caption;

    final Widget body;
    if (isVideo) {
      body = switch (_phase) {
        _VideoPhase.loading => _buildVideoLoading(),
        _VideoPhase.ready => _buildVideo(),
        _VideoPhase.failed => _buildVideoFailed(l10n),
      };
    } else if (content.hasMedia) {
      body = _buildImage(l10n);
    } else if (caption != null) {
      // A text card is content in its own right, never a failed picture.
      body = _TextCard(text: caption);
    } else {
      _reportMediaError();
      body = _MediaFallback(
        message: l10n.humorMediaUnavailable,
        onNext: _nextAction(l10n),
      );
    }

    final attribution = content.attribution;
    return KeyedSubtree(
      key: ValueKey(content.contentId),
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            body,
            Positioned(
              left: AppSpacing.md,
              top: AppSpacing.md,
              right: AppSpacing.md + 48,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Chip(label: _categoryLabel(l10n, content.category)),
                  if (attribution != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _AttributionLabel(
                      attribution: attribution,
                      verifiedLabel: l10n.humorAttributionVerified,
                    ),
                  ],
                ],
              ),
            ),
            if (isVideo && _video != null)
              Positioned(
                right: AppSpacing.md,
                top: AppSpacing.md,
                child: IconButton.filledTonal(
                  onPressed: () => unawaited(_toggleMute()),
                  icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                ),
              ),
          ],
        ),
      ),
    );
  }

  _FallbackAction? _nextAction(AppLocalizations l10n) {
    if (widget.onSkipUnplayable == null) {
      return null;
    }
    return _FallbackAction(
      label: l10n.humorMediaNext,
      onPressed: _skipUnplayable,
    );
  }

  /// The item's own still (never a stand-in) behind whatever is on top.
  Widget? _poster() {
    final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
    if (thumb == null) {
      return null;
    }
    return Image(
      image: thumb,
      fit: _fitFor(widget.content.aspectRatio),
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }

  /// Bounded by the init timeout and the single retry, so it always ends.
  Widget _buildVideoLoading() {
    final poster = _poster();
    final caption = _caption;
    return Stack(
      fit: StackFit.expand,
      children: [
        ?poster,
        const Center(child: CircularProgressIndicator()),
        if (caption != null) _CaptionOverlay(text: caption),
      ],
    );
  }

  Widget _buildVideo() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return _buildVideoLoading();
    }
    final caption = _caption;
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: _fitFor(video.value.aspectRatio),
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: video.value.size.width,
            height: video.value.size.height,
            child: VideoPlayer(video),
          ),
        ),
        if (caption != null) _CaptionOverlay(text: caption),
      ],
    );
  }

  /// A clip that cannot play: its poster (never the .mp4 drawn as an image)
  /// dimmed behind a plain message, a one-time "Try again" and "Next". The
  /// item's text, if any, stays readable — shown once, not also as a caption.
  Widget _buildVideoFailed(AppLocalizations l10n) {
    final poster = _poster();
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null) ...[
          poster,
          ColoredBox(color: theme.colorScheme.scrim.withValues(alpha: 0.6)),
        ],
        _MediaFallback(
          icon: Icons.videocam_off_outlined,
          message: l10n.humorVideoLoadFailed,
          caption: _caption,
          onRetry: _canRetryManually
              ? _FallbackAction(
                  label: l10n.humorTryAgain,
                  onPressed: _retryManually,
                )
              : null,
          onNext: _nextAction(l10n),
        ),
      ],
    );
  }

  /// An image or meme — a still, or an animated WebP/GIF that Flutter's image
  /// pipeline decodes and loops by itself. Until the first frame arrives the
  /// item's own poster (when it has a separate one) shows with a spinner; the
  /// wait is bounded by [HumorContentPlayer.imageLoadTimeout].
  Widget _buildImage(AppLocalizations l10n) {
    final content = widget.content;
    final url = _imageUrl;
    final image = MevoraNetworkImages.provider(url);
    if (image == null) {
      _reportMediaError();
      return _MediaFallback(
        message: l10n.humorMediaUnavailable,
        caption: _caption,
        onNext: _nextAction(l10n),
      );
    }
    if (_imageTimedOut) {
      return _buildImageFailed(l10n);
    }
    final caption = _caption;
    final poster = content.thumbUrl != url ? _poster() : null;
    // The caption rides on the picture (or its poster while loading) and the
    // error fallback carries it instead, so the text is on screen exactly
    // once either way.
    return Image(
      key: ValueKey(_imageLoad),
      image: image,
      fit: _fitFor(content.aspectRatio),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        final shown = wasSynchronouslyLoaded || frame != null;
        if (shown) {
          _onImageShown();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            if (!shown) ...[
              ?poster,
              const Center(child: CircularProgressIndicator()),
            ],
            child,
            if (caption != null) _CaptionOverlay(text: caption),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _onImageError();
        return _buildImageFailed(l10n);
      },
    );
  }

  /// An image that cannot be shown: its poster (if it has its own) dimmed
  /// behind a plain message, a one-time "Try again" and "Next".
  Widget _buildImageFailed(AppLocalizations l10n) {
    final poster = widget.content.thumbUrl != _imageUrl ? _poster() : null;
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (poster != null) ...[
          poster,
          ColoredBox(color: theme.colorScheme.scrim.withValues(alpha: 0.6)),
        ],
        _MediaFallback(
          message: l10n.humorMediaUnavailable,
          caption: _caption,
          onRetry: _canRetryManually
              ? _FallbackAction(
                  label: l10n.humorTryAgain,
                  onPressed: _retryImage,
                )
              : null,
          onNext: _nextAction(l10n),
        ),
      ],
    );
  }

  static String _categoryLabel(AppLocalizations l10n, HumorCategory category) {
    return switch (category) {
      HumorCategory.sarcasm => l10n.humorCategorySarcasm,
      HumorCategory.absurd => l10n.humorCategoryAbsurd,
      HumorCategory.silly => l10n.humorCategorySilly,
      HumorCategory.romantic => l10n.humorCategoryRomantic,
      HumorCategory.dark => l10n.humorCategoryDark,
      HumorCategory.meme => l10n.humorCategoryMeme,
      HumorCategory.dry => l10n.humorCategoryDry,
      HumorCategory.wordplay => l10n.humorCategoryWordplay,
      HumorCategory.situational => l10n.humorCategorySituational,
      HumorCategory.cringe => l10n.humorCategoryCringe,
      HumorCategory.teasing => l10n.humorCategoryTeasing,
    };
  }
}

class _ZeroSizeVideo implements Exception {
  const _ZeroSizeVideo();
}

/// One in-flight [VideoPlayerController.initialize], bounded by a timeout and
/// cancellable when the card changes or goes away. It keeps its own timer
/// rather than using [Future.timeout] so a cancel leaves nothing scheduled.
class _VideoLoad {
  _VideoLoad(this.controller);

  final VideoPlayerController controller;
  final _done = Completer<void>();
  Timer? _timer;

  Future<void> initialize(Duration timeout) {
    _timer = Timer(
      timeout,
      () => _finish(TimeoutException('Humor video load timed out', timeout)),
    );
    unawaited(
      Future<void>.sync(
        controller.initialize,
      ).then<void>((_) => _finish(), onError: (Object error) => _finish(error)),
    );
    return _done.future;
  }

  void cancel() => _finish(StateError('Humor video load cancelled'));

  void _finish([Object? error]) {
    _timer?.cancel();
    if (_done.isCompleted) {
      return;
    }
    if (error == null) {
      _done.complete();
    } else {
      _done.completeError(error);
    }
  }
}

class _CaptionOverlay extends StatelessWidget {
  const _CaptionOverlay({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      left: AppSpacing.lg,
      right: AppSpacing.lg,
      bottom: AppSpacing.xl,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.scrim.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onInverseSurface,
              height: 1.3,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onInverseSurface,
          ),
        ),
      ),
    );
  }
}

/// Small provider credit, e.g. "GIPHY · @username" with a check when the
/// creator is verified. Provider terms require it on their content.
class _AttributionLabel extends StatelessWidget {
  const _AttributionLabel({
    required this.attribution,
    required this.verifiedLabel,
  });

  final HumorContentAttribution attribution;
  final String verifiedLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onInverseSurface.withValues(alpha: 0.9);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                attribution.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
            ),
            if (attribution.verified) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.verified,
                size: 12,
                color: color,
                semanticLabel: verifiedLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FallbackAction {
  const _FallbackAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// Media that cannot be shown: an honest notice, the item's text (if any) as
/// the body — shown once, never also as a caption overlay — and the ways on.
class _MediaFallback extends StatelessWidget {
  const _MediaFallback({
    required this.message,
    this.icon = Icons.hide_image_outlined,
    this.caption,
    this.onRetry,
    this.onNext,
  });

  final String message;
  final IconData icon;
  final String? caption;
  final _FallbackAction? onRetry;
  final _FallbackAction? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onInverseSurface;
    final caption = this.caption;
    final retry = onRetry;
    final next = onNext;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color.withValues(alpha: 0.85),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Flexible(
                child: Text(
                  caption,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.fade,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: color,
                    height: 1.35,
                  ),
                ),
              ),
            ],
            if (retry != null || next != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (retry != null)
                    OutlinedButton.icon(
                      onPressed: retry.onPressed,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                        side: BorderSide(color: color.withValues(alpha: 0.6)),
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(retry.label),
                    ),
                  if (next != null)
                    FilledButton.icon(
                      onPressed: next.onPressed,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: Text(next.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A joke that is text by design (curated Mevora content): large, centred
/// and calm, never framed as missing media.
class _TextCard extends StatelessWidget {
  const _TextCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surfaceContainerHigh,
            Color.alphaBlend(
              scheme.primaryContainer.withValues(alpha: 0.45),
              scheme.surfaceContainerHigh,
            ),
          ],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.xxl,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    (constraints.maxHeight - AppSpacing.xxl - AppSpacing.xl)
                        .clamp(0, double.infinity),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.format_quote_rounded,
                      size: 36,
                      color: scheme.primary.withValues(alpha: 0.35),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      text,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
