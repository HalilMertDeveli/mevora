import 'dart:async';

import 'package:flutter/material.dart';
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

/// Full-bleed humor media: video (autoplay/mute/loop) or image/meme/text.
///
/// The card never stays on an endless spinner or a blank frame: a video that
/// fails, stalls past [videoInitTimeout] or reports a zero size falls back to
/// its thumbnail (or its text), and [onMediaError] hears about it once.
class HumorContentPlayer extends StatefulWidget {
  const HumorContentPlayer({
    super.key,
    required this.content,
    this.isActive = true,
    this.replayToken = 0,
    this.onMediaError,
    this.videoControllerFactory,
  });

  /// How long a video may take to initialise before it counts as broken.
  static const videoInitTimeout = Duration(seconds: 12);

  final HumorContent content;

  /// Only the active card plays; every other card is kept paused.
  final bool isActive;

  /// A change replays the active card's video from the start. Ignored while
  /// the card is not active, so an off-screen card never reloads anything.
  final int replayToken;

  /// Called once per item, with its contentId, when its media cannot be shown.
  final ValueChanged<String>? onMediaError;

  /// Defaults to [VideoPlayerController.networkUrl].
  final HumorVideoControllerFactory? videoControllerFactory;

  @override
  State<HumorContentPlayer> createState() => _HumorContentPlayerState();
}

class _HumorContentPlayerState extends State<HumorContentPlayer> {
  /// Media at least this wide relative to its height (landscape, square or
  /// only slightly tall) is letterboxed on black so nothing is cropped; only
  /// clearly portrait media fills the card.
  static const _letterboxMinAspectRatio = 0.8;

  VideoPlayerController? _video;
  _VideoLoad? _load;

  /// Bumped whenever the card's media is torn down, so a load that resolves
  /// late can tell it no longer belongs to this card.
  var _generation = 0;
  var _muted = true;
  var _videoError = false;
  var _errorReported = false;

  bool get _isVideo {
    final content = widget.content;
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

  String? get _caption =>
      widget.content.hasText ? widget.content.textBody : null;

  @override
  void initState() {
    super.initState();
    _startMedia();
  }

  @override
  void didUpdateWidget(covariant HumorContentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.content;
    final next = widget.content;
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
  }

  @override
  void dispose() {
    _resetMedia();
    super.dispose();
  }

  /// Runs from initState/didUpdateWidget, so a build always follows and the
  /// synchronous failures below need no setState.
  void _startMedia() {
    if (!_isVideo) {
      return;
    }
    final url = widget.content.downloadUrl;
    VideoPlayerController? controller;
    if (MevoraNetworkImages.isHttpUrl(url)) {
      try {
        final factory =
            widget.videoControllerFactory ?? VideoPlayerController.networkUrl;
        controller = factory(Uri.parse(url!));
      } catch (_) {
        controller = null;
      }
    }
    if (controller == null) {
      _videoError = true;
      _reportMediaError();
      return;
    }
    unawaited(_initVideo(controller, _generation));
  }

  /// Drops whatever media this card holds: the bound controller and any load
  /// still in flight (which disposes its own controller once it unwinds).
  void _resetMedia() {
    _generation++;
    _load?.cancel();
    _load = null;
    final video = _video;
    _video = null;
    if (video != null) {
      video.removeListener(_onVideoValue);
      unawaited(_disposeQuietly(video));
    }
    _videoError = false;
    _errorReported = false;
  }

  bool _isCurrent(int generation) => mounted && generation == _generation;

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
        // A 0x0 clip (corrupt or audio-only) would paint nothing at all.
        throw StateError('Humor video reported no frame size');
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!_isCurrent(generation)) {
        unawaited(_disposeQuietly(controller));
        return;
      }
      controller.addListener(_onVideoValue);
      setState(() {
        _video = controller;
        _videoError = false;
      });
      _syncPlayback();
    } catch (_) {
      // Never wait on the dispose first: a stalled platform player may not
      // release promptly, and the card must leave the spinner now.
      unawaited(_disposeQuietly(controller));
      _failVideo(generation);
    } finally {
      if (identical(_load, load)) {
        _load = null;
      }
    }
  }

  /// A clip that breaks after it started playing gets the same fallback.
  void _onVideoValue() {
    final video = _video;
    if (video == null || !video.value.hasError) {
      return;
    }
    video.removeListener(_onVideoValue);
    _video = null;
    // Not from inside the controller's own notification.
    scheduleMicrotask(() => unawaited(_disposeQuietly(video)));
    _failVideo(_generation);
  }

  void _failVideo(int generation) {
    if (!_isCurrent(generation)) {
      return;
    }
    setState(() => _videoError = true);
    _reportMediaError();
  }

  /// Tells [HumorContentPlayer.onMediaError] once per item, after the frame,
  /// so a listener may safely rebuild its own state.
  void _reportMediaError() {
    if (_errorReported) {
      return;
    }
    _errorReported = true;
    final generation = _generation;
    final contentId = widget.content.contentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCurrent(generation)) {
        widget.onMediaError?.call(contentId);
      }
    });
  }

  void _syncPlayback() {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      return;
    }
    if (widget.isActive) {
      unawaited(_quietly(video.play));
    } else {
      unawaited(_quietly(video.pause));
    }
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
        if (mounted && identical(_video, video) && widget.isActive) {
          await video.play();
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

    final Widget body;
    if (isVideo && !_videoError) {
      body = _buildVideo();
    } else if (isVideo) {
      body = _buildVideoFallback(l10n);
    } else if (content.hasMedia) {
      body = _buildImage(l10n);
    } else {
      body = _TextBody(text: _caption ?? l10n.humorMediaUnavailable);
    }

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
              child: _Chip(label: _categoryLabel(l10n, content.category)),
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

  Widget _buildVideo() {
    final video = _video;
    final caption = _caption;
    if (video == null || !video.value.isInitialized) {
      // Loading is bounded by videoInitTimeout, so this spinner always ends.
      final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image(
              image: thumb,
              fit: _fitFor(widget.content.aspectRatio),
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const Center(child: CircularProgressIndicator()),
          if (caption != null) _CaptionOverlay(text: caption),
        ],
      );
    }
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

  /// A clip that cannot play shows its thumbnail (never the .mp4 URL drawn
  /// as an image) and says so; without a usable thumbnail, its text.
  Widget _buildVideoFallback(AppLocalizations l10n) {
    final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
    if (thumb == null) {
      return _MediaFallback(
        message: l10n.humorMediaUnavailable,
        caption: _caption,
      );
    }
    return _buildPicture(thumb, l10n, notice: l10n.humorMediaUnavailable);
  }

  Widget _buildImage(AppLocalizations l10n) {
    final content = widget.content;
    final downloadUrl = content.downloadUrl;
    final url = downloadUrl != null && downloadUrl.isNotEmpty
        ? downloadUrl
        : content.thumbUrl;
    final image = MevoraNetworkImages.provider(url);
    if (image == null) {
      _reportMediaError();
      return _MediaFallback(
        message: l10n.humorMediaUnavailable,
        caption: _caption,
      );
    }
    return _buildPicture(image, l10n);
  }

  /// The caption rides on the loaded picture and the error fallback carries
  /// it instead, so the text is on screen exactly once either way.
  Widget _buildPicture(
    ImageProvider image,
    AppLocalizations l10n, {
    String? notice,
  }) {
    final caption = _caption;
    return Image(
      image: image,
      fit: _fitFor(widget.content.aspectRatio),
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (notice != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: _Notice(text: notice),
                ),
              ),
            if (caption != null) _CaptionOverlay(text: caption),
          ],
        );
      },
      errorBuilder: (context, error, stackTrace) {
        _reportMediaError();
        return _MediaFallback(
          message: l10n.humorMediaUnavailable,
          caption: caption,
        );
      },
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

/// A small pill over a still that stands in for a clip that cannot play.
class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onInverseSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam_off_outlined, size: 18, color: color),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Media that cannot be shown: an honest notice, plus the item's text (if
/// any) as the body, shown once and never also as a caption overlay.
class _MediaFallback extends StatelessWidget {
  const _MediaFallback({required this.message, this.caption});

  final String message;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onInverseSurface;
    final caption = this.caption;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hide_image_outlined,
              size: 32,
              color: color.withValues(alpha: 0.7),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color.withValues(alpha: 0.8),
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
          ],
        ),
      ),
    );
  }
}

class _TextBody extends StatelessWidget {
  const _TextBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onInverseSurface,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
