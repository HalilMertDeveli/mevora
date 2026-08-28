import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/responsive/responsive_media.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_media_controller_stats.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Full-bleed humor media: MP4, Giphy stream, YouTube embed, or image/meme/text.
///
/// Never throws out of build — broken media reports [onMediaError] instead.
class HumorContentPlayer extends StatefulWidget {
  const HumorContentPlayer({
    super.key,
    required this.content,
    this.isActive = true,
    this.replayToken = 0,
    this.onMediaError,
    this.mediaLoadTimeout = const Duration(seconds: 12),
  });

  /// When true, skips VideoPlayer / YouTube iframe init (widget stress tests).
  /// Still exercises active/inactive dispose paths via [HumorMediaControllerStats]
  /// lightweight stubs when [debugTrackStubControllers] is also true.
  @visibleForTesting
  static bool debugDisableHeavyMedia = false;

  /// Counts stub create/dispose when heavy media is disabled (leak accounting).
  @visibleForTesting
  static bool debugTrackStubControllers = false;

  final HumorContent content;
  final bool isActive;
  final int replayToken;
  final ValueChanged<String>? onMediaError;

  /// Soft ceiling so a hung CDN/iframe never spins forever.
  final Duration mediaLoadTimeout;

  @override
  State<HumorContentPlayer> createState() => _HumorContentPlayerState();
}

class _HumorContentPlayerState extends State<HumorContentPlayer> {
  VideoPlayerController? _video;
  YoutubePlayerController? _youtube;
  StreamSubscription<YoutubePlayerValue>? _youtubeSub;
  VoidCallback? _videoListener;

  var _muted = true;
  var _videoError = false;
  var _initializing = false;
  var _errorReported = false;
  Timer? _loadWatchdog;
  var _stubYoutubeHeld = false;
  var _stubVideoHeld = false;

  /// Cancel token — incremented on dispose / content change so stale boots abort.
  var _bootGeneration = 0;

  bool get _isYoutube => widget.content.isYoutube;

  bool get _isDirectVideo {
    if (_isYoutube) {
      return false;
    }
    final url = widget.content.downloadUrl ?? '';
    if (url.isEmpty) {
      return false;
    }
    // Never feed YouTube HTML URLs into VideoPlayer.
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return false;
    }
    if (widget.content.type == HumorContentType.video) {
      return true;
    }
    return lower.endsWith('.mp4') ||
        lower.contains('video/mp4') ||
        lower.contains('gtv-videos-bucket') ||
        lower.contains('giphy.com');
  }

  void _logState(String phase) {
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      'HumorContentPlayer[$phase] '
      'provider=${widget.content.provider} '
      'contentId=${widget.content.contentId} '
      'sourceId=${widget.content.sourceId} '
      'yt=$_isYoutube direct=$_isDirectVideo '
      'active=${widget.isActive} err=$_videoError '
      'bootGen=$_bootGeneration',
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_boot());
  }

  @override
  void didUpdateWidget(covariant HumorContentPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content.contentId != widget.content.contentId ||
        oldWidget.replayToken != widget.replayToken) {
      unawaited(_restartForContentChange());
      return;
    }
    if (oldWidget.isActive != widget.isActive) {
      if (widget.isActive) {
        // Offscreen pages release controllers; re-boot when becoming active.
        if (!_videoError &&
            ((_isYoutube && _youtube == null) ||
                (_isDirectVideo && _video == null))) {
          unawaited(_boot());
        } else {
          _syncPlayback();
        }
      } else {
        // Keep at most one heavy decoder/iframe alive across PageView cache.
        unawaited(_disposeMedia());
        if (mounted) {
          setState(() {
            _videoError = false;
          });
        }
      }
    }
  }

  Future<void> _restartForContentChange() async {
    _errorReported = false;
    await _disposeMedia();
    if (!mounted) {
      return;
    }
    _videoError = false;
    await _boot();
  }

  Future<void> _boot() async {
    final gen = ++_bootGeneration;
    _logState('boot-start');
    _armLoadWatchdog(gen);
    try {
      if (HumorContentPlayer.debugDisableHeavyMedia) {
        _cancelLoadWatchdog();
        if (!widget.isActive) {
          _logState('boot-stub-deferred');
          return;
        }
        if (HumorContentPlayer.debugTrackStubControllers) {
          if (_isYoutube) {
            HumorMediaControllerStats.onYoutubeCreated();
            _stubYoutubeHeld = true;
          } else if (_isDirectVideo) {
            HumorMediaControllerStats.onVideoCreated();
            _stubVideoHeld = true;
          }
        }
        _logState('boot-stub');
        return;
      }
      if (_isYoutube) {
        // Lazy: only create the iframe when the card is the active page.
        if (!widget.isActive) {
          _cancelLoadWatchdog();
          _logState('boot-yt-deferred');
          return;
        }
        await _initYoutube(gen);
      } else if (_isDirectVideo) {
        // Same lazy rule as YouTube — prevents N VideoPlayerControllers in
        // PageView cache during fast swipe stress.
        if (!widget.isActive) {
          _cancelLoadWatchdog();
          _logState('boot-video-deferred');
          return;
        }
        await _initVideo(gen);
      } else {
        _cancelLoadWatchdog();
      }
    } catch (error, stack) {
      debugPrint('HumorContentPlayer boot failed: $error\n$stack');
      if (gen == _bootGeneration) {
        _markError();
      }
    }
  }

  void _armLoadWatchdog(int gen) {
    _cancelLoadWatchdog();
    final timeout = widget.mediaLoadTimeout;
    if (timeout <= Duration.zero) {
      return;
    }
    _loadWatchdog = Timer(timeout, () {
      if (_isStale(gen) || _videoError) {
        return;
      }
      // Direct video: ready once initialized. YouTube: wait for player state
      // (controller may exist while iframe is still broken/hung).
      final videoReady = _video != null && _video!.value.isInitialized;
      if (videoReady) {
        return;
      }
      if (_isYoutube && _youtube != null) {
        // Controller exists but never reached a playable state → soft-fail.
        debugPrint(
          'HumorContentPlayer youtube-load-timeout '
          'contentId=${widget.content.contentId} '
          'after=${timeout.inMilliseconds}ms',
        );
        _markError();
        return;
      }
      debugPrint(
        'HumorContentPlayer load-timeout '
        'contentId=${widget.content.contentId} '
        'after=${timeout.inMilliseconds}ms',
      );
      _markError();
    });
  }

  void _cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  bool _isStale(int gen) => gen != _bootGeneration || !mounted;

  void _markError() {
    if (!mounted) {
      return;
    }
    _cancelLoadWatchdog();
    setState(() => _videoError = true);
    if (_errorReported) {
      return;
    }
    _errorReported = true;
    _logState('media-error');
    widget.onMediaError?.call(widget.content.contentId);
  }

  Future<void> _initYoutube(int gen) async {
    final videoId = widget.content.youtubeVideoId;
    if (videoId == null || videoId.isEmpty || _initializing) {
      if (videoId == null || videoId.isEmpty) {
        _markError();
      }
      return;
    }
    _initializing = true;
    try {
      final controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: widget.isActive,
        params: const YoutubePlayerParams(
          mute: true,
          showControls: false,
          showFullscreenButton: false,
          loop: true,
          strictRelatedVideos: true,
        ),
      );
      HumorMediaControllerStats.onYoutubeCreated();
      if (_isStale(gen)) {
        HumorMediaControllerStats.onYoutubeDisposed();
        await controller.close();
        return;
      }
      await _youtubeSub?.cancel();
      _youtubeSub = controller.listen((value) {
        if (_isStale(gen)) {
          return;
        }
        if (value.error != YoutubeError.none) {
          debugPrint(
            'Humor YouTube player error code=${value.error.code} '
            'contentId=${widget.content.contentId}',
          );
          _markError();
          return;
        }
        // Iframe became usable — stop the hung-load watchdog.
        final state = value.playerState;
        if (state == PlayerState.playing ||
            state == PlayerState.paused ||
            state == PlayerState.cued) {
          _cancelLoadWatchdog();
        }
      });
      setState(() {
        _youtube = controller;
        _videoError = false;
      });
      _logState('yt-ready');
      _syncPlayback();
    } catch (error, stack) {
      debugPrint('Humor YouTube init failed: $error\n$stack');
      if (!_isStale(gen)) {
        _markError();
      }
    } finally {
      if (gen == _bootGeneration) {
        _initializing = false;
      }
    }
  }

  Future<void> _initVideo(int gen) async {
    final url = widget.content.downloadUrl;
    if (url == null || url.isEmpty || _initializing) {
      if (url == null || url.isEmpty) {
        _markError();
      }
      return;
    }
    // Belt-and-suspenders: never treat YouTube URLs as VideoPlayer sources.
    final lower = url.toLowerCase();
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      _markError();
      return;
    }
    _initializing = true;
    VideoPlayerController? controller;
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) {
        _markError();
        return;
      }
      controller = VideoPlayerController.networkUrl(uri);
      HumorMediaControllerStats.onVideoCreated();
      await controller.initialize();
      if (_isStale(gen)) {
        HumorMediaControllerStats.onVideoDisposed();
        await controller.dispose();
        return;
      }
      final size = controller.value.size;
      if (size.width <= 0 || size.height <= 0) {
        HumorMediaControllerStats.onVideoDisposed();
        await controller.dispose();
        _markError();
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (_isStale(gen)) {
        HumorMediaControllerStats.onVideoDisposed();
        await controller.dispose();
        return;
      }
      void listener() {
        final c = _video;
        if (c == null || _isStale(gen)) {
          return;
        }
        if (c.value.hasError) {
          debugPrint(
            'Humor video player error=${c.value.errorDescription} '
            'contentId=${widget.content.contentId}',
          );
          _markError();
        }
      }
      controller.addListener(listener);
      _videoListener = listener;
      setState(() {
        _video = controller;
        _videoError = false;
      });
      controller = null;
      _cancelLoadWatchdog();
      _logState('video-ready');
      _syncPlayback();
    } catch (error, stack) {
      debugPrint('Humor video init failed: $error\n$stack');
      final listener = _videoListener;
      if (listener != null) {
        controller?.removeListener(listener);
        _videoListener = null;
      }
      await controller?.dispose();
      if (controller != null) {
        HumorMediaControllerStats.onVideoDisposed();
      }
      if (!_isStale(gen)) {
        _markError();
      }
    } finally {
      if (gen == _bootGeneration) {
        _initializing = false;
      }
    }
  }

  void _syncPlayback() {
    try {
      final youtube = _youtube;
      if (youtube != null) {
        if (widget.isActive) {
          unawaited(youtube.playVideo());
        } else {
          unawaited(youtube.pauseVideo());
        }
      }
      final video = _video;
      if (video == null || !video.value.isInitialized) {
        return;
      }
      if (widget.isActive) {
        unawaited(video.play());
      } else {
        unawaited(video.pause());
      }
    } catch (error, stack) {
      debugPrint('Humor playback sync failed: $error\n$stack');
      _markError();
    }
  }

  void _releaseStubs() {
    if (_stubYoutubeHeld) {
      _stubYoutubeHeld = false;
      HumorMediaControllerStats.onYoutubeDisposed();
    }
    if (_stubVideoHeld) {
      _stubVideoHeld = false;
      HumorMediaControllerStats.onVideoDisposed();
    }
  }

  Future<void> _disposeMedia() async {
    _cancelLoadWatchdog();
    _bootGeneration += 1;
    _releaseStubs();
    final ytSub = _youtubeSub;
    _youtubeSub = null;
    await ytSub?.cancel();

    final youtube = _youtube;
    _youtube = null;
    if (youtube != null) {
      try {
        await youtube.close();
      } catch (_) {}
      HumorMediaControllerStats.onYoutubeDisposed();
    }
    final video = _video;
    final videoListener = _videoListener;
    _video = null;
    _videoListener = null;
    if (video != null) {
      try {
        if (videoListener != null) {
          video.removeListener(videoListener);
        }
        await video.dispose();
      } catch (_) {}
      HumorMediaControllerStats.onVideoDisposed();
    }
  }

  @override
  void dispose() {
    _releaseStubs();
    unawaited(_disposeMedia());
    super.dispose();
  }

  Future<void> _toggleMute() async {
    try {
      final youtube = _youtube;
      if (youtube != null) {
        final next = !_muted;
        if (next) {
          await youtube.mute();
        } else {
          await youtube.unMute();
        }
        if (mounted) {
          setState(() => _muted = next);
        }
        return;
      }
      final video = _video;
      if (video == null) {
        return;
      }
      final next = !_muted;
      await video.setVolume(next ? 0 : 1);
      if (mounted) {
        setState(() => _muted = next);
      }
    } catch (_) {}
  }

  Future<void> _openSource() async {
    final raw =
        widget.content.sourceUrl ??
        widget.content.embedUrl ??
        widget.content.downloadUrl;
    if (raw == null || raw.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return KeyedSubtree(
      key: ValueKey('${widget.content.contentId}-${widget.replayToken}'),
      child: ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
              return const SizedBox.shrink();
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                if (HumorContentPlayer.debugDisableHeavyMedia)
                  _TextBody(
                    text: widget.content.textBody ?? l10n.humorEmptyFeed,
                  )
                else if (_isYoutube && !_videoError)
                  _buildYoutube(theme, l10n, constraints)
                else if (_isDirectVideo && !_videoError)
                  _buildVideo(theme, l10n, constraints)
                else if (widget.content.hasMedia &&
                    !_isDirectVideo &&
                    !_isYoutube)
                  _buildImage(theme, l10n)
                else if ((_isDirectVideo || _isYoutube) &&
                    _videoError &&
                    widget.content.thumbUrl != null)
                  _buildImage(theme, l10n)
                else if (_videoError)
                  _TextBody(text: l10n.humorMediaErrorSkip)
                else
                  _TextBody(
                    text: widget.content.textBody ?? l10n.humorEmptyFeed,
                  ),
                if (widget.content.hasText &&
                    widget.content.textBody != null &&
                    (widget.content.type != HumorContentType.text ||
                        widget.content.hasMedia))
                  _CaptionOverlay(text: widget.content.textBody!),
                Positioned(
                  left: AppSpacing.md,
                  top: AppSpacing.md,
                  child: _Chip(
                    label: _categoryLabel(l10n, widget.content.category),
                  ),
                ),
                if (widget.content.attributionRequired)
                  Positioned(
                    left: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: _Chip(
                      label: widget.content.isGiphy
                          ? l10n.humorAttributionGiphy
                          : widget.content.isYoutube
                          ? l10n.humorAttributionYoutube
                          : l10n.humorAttributionGeneric,
                    ),
                  ),
                if ((_isDirectVideo || _isYoutube) &&
                    (_video != null || _youtube != null) &&
                    !_videoError)
                  Positioned(
                    right: AppSpacing.md,
                    top: AppSpacing.md,
                    child: IconButton.filledTonal(
                      onPressed: () => unawaited(_toggleMute()),
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                    ),
                  ),
                if (_isYoutube && _videoError)
                  Positioned(
                    right: AppSpacing.md,
                    bottom: AppSpacing.md,
                    child: TextButton.icon(
                      onPressed: () => unawaited(_openSource()),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(l10n.humorOpenOnYoutube),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildYoutube(
    ThemeData theme,
    AppLocalizations l10n,
    BoxConstraints constraints,
  ) {
    final youtube = _youtube;
    if (youtube == null) {
      final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image(
              image: thumb,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            )
          else
            const ColoredBox(color: Colors.black),
          if (widget.isActive)
            const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
      return const SizedBox.shrink();
    }
    final ratio = ResponsiveMedia.clampAspect(
      widget.content.aspectRatio,
      fallback: ResponsiveMedia.storyAspect,
    );
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: ratio,
          child: YoutubePlayer(
            controller: youtube,
            aspectRatio: ratio,
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(
    ThemeData theme,
    AppLocalizations l10n,
    BoxConstraints constraints,
  ) {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image(
              image: thumb,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            )
          else
            const ColoredBox(color: Colors.black),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    final size = video.value.size;
    if (size.width <= 0 ||
        size.height <= 0 ||
        constraints.maxWidth <= 0 ||
        constraints.maxHeight <= 0) {
      return _TextBody(text: l10n.humorMediaErrorSkip);
    }
    final videoAspect = size.width / size.height;
    // Portrait / near-square: full-bleed cover. Landscape: contain so content
    // is not horizontally crushed on tall phone frames.
    final fit = videoAspect >= 1.15 ? BoxFit.contain : BoxFit.cover;
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: VideoPlayer(video),
        ),
      ),
    );
  }

  Widget _buildImage(ThemeData theme, AppLocalizations l10n) {
    final image = MevoraNetworkImages.provider(
      widget.content.downloadUrl ?? widget.content.thumbUrl,
    );
    if (image == null) {
      return _TextBody(text: widget.content.textBody ?? l10n.humorEmptyFeed);
    }
    final ratio = widget.content.aspectRatio;
    final fit = (ratio != null && ratio >= 1.15) ? BoxFit.contain : BoxFit.cover;
    return ColoredBox(
      color: Colors.black,
      child: Image(
        image: image,
        fit: fit,
        alignment: Alignment.center,
        errorBuilder: (_, _, _) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _markError();
            }
          });
          return _TextBody(
            text: widget.content.textBody ?? l10n.humorMediaErrorSkip,
          );
        },
      ),
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
