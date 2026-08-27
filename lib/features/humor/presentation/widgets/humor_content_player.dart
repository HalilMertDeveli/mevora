import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Full-bleed humor media: MP4, Giphy stream, YouTube embed, or image/meme/text.
class HumorContentPlayer extends StatefulWidget {
  const HumorContentPlayer({
    super.key,
    required this.content,
    this.isActive = true,
    this.replayToken = 0,
  });

  final HumorContent content;
  final bool isActive;
  final int replayToken;

  @override
  State<HumorContentPlayer> createState() => _HumorContentPlayerState();
}

class _HumorContentPlayerState extends State<HumorContentPlayer> {
  VideoPlayerController? _video;
  YoutubePlayerController? _youtube;
  var _muted = true;
  var _videoError = false;
  var _initializing = false;

  bool get _isYoutube => widget.content.isYoutube;

  bool get _isDirectVideo {
    if (_isYoutube) {
      return false;
    }
    final url = widget.content.downloadUrl ?? '';
    if (widget.content.type == HumorContentType.video) {
      return url.isNotEmpty;
    }
    return url.toLowerCase().endsWith('.mp4') ||
        url.contains('video/mp4') ||
        url.contains('gtv-videos-bucket') ||
        url.contains('giphy.com');
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
      unawaited(_disposeMedia());
      _videoError = false;
      unawaited(_boot());
      return;
    }
    if (oldWidget.isActive != widget.isActive) {
      _syncPlayback();
    }
  }

  Future<void> _boot() async {
    if (_isYoutube) {
      await _initYoutube();
    } else if (_isDirectVideo) {
      await _initVideo();
    }
  }

  Future<void> _initYoutube() async {
    final videoId = widget.content.youtubeVideoId;
    if (videoId == null || videoId.isEmpty || _initializing) {
      return;
    }
    _initializing = true;
    try {
      final controller = YoutubePlayerController(
        params: const YoutubePlayerParams(
          mute: true,
          showControls: false,
          showFullscreenButton: false,
          loop: true,
          strictRelatedVideos: true,
        ),
      );
      await controller.loadVideoById(videoId: videoId);
      if (!mounted) {
        await controller.close();
        return;
      }
      setState(() {
        _youtube = controller;
        _videoError = false;
      });
      _syncPlayback();
    } catch (_) {
      if (mounted) {
        setState(() => _videoError = true);
      }
    } finally {
      _initializing = false;
    }
  }

  Future<void> _initVideo() async {
    final url = widget.content.downloadUrl;
    if (url == null || url.isEmpty || _initializing) {
      return;
    }
    _initializing = true;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(_muted ? 0 : 1);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoError = false;
      });
      _syncPlayback();
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() => _videoError = true);
      }
    } finally {
      _initializing = false;
    }
  }

  void _syncPlayback() {
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
  }

  Future<void> _disposeMedia() async {
    final youtube = _youtube;
    _youtube = null;
    if (youtube != null) {
      await youtube.close();
    }
    final video = _video;
    _video = null;
    if (video != null) {
      await video.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(_disposeMedia());
    super.dispose();
  }

  Future<void> _toggleMute() async {
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isYoutube && !_videoError)
              _buildYoutube(theme, l10n)
            else if (_isDirectVideo && !_videoError)
              _buildVideo(theme, l10n)
            else if (widget.content.hasMedia && !_isDirectVideo && !_isYoutube)
              _buildImage(theme, l10n)
            else if ((_isDirectVideo || _isYoutube) &&
                _videoError &&
                widget.content.thumbUrl != null)
              _buildImage(theme, l10n)
            else
              _TextBody(
                text: widget.content.textBody ?? l10n.humorEmptyFeed,
              ),
            if (widget.content.hasText &&
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
                  label: widget.content.provider == 'giphy'
                      ? l10n.humorAttributionGiphy
                      : widget.content.provider == 'youtube'
                      ? l10n.humorAttributionYoutube
                      : l10n.humorAttributionGeneric,
                ),
              ),
            if ((_isDirectVideo || _isYoutube) &&
                (_video != null || _youtube != null))
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
        ),
      ),
    );
  }

  Widget _buildYoutube(ThemeData theme, AppLocalizations l10n) {
    final youtube = _youtube;
    if (youtube == null) {
      final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image(image: thumb, fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.black),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return YoutubePlayer(
      controller: youtube,
      aspectRatio: widget.content.aspectRatio ?? 9 / 16,
    );
  }

  Widget _buildVideo(ThemeData theme, AppLocalizations l10n) {
    final video = _video;
    if (video == null || !video.value.isInitialized) {
      final thumb = MevoraNetworkImages.provider(widget.content.thumbUrl);
      return Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            Image(image: thumb, fit: BoxFit.cover)
          else
            const ColoredBox(color: Colors.black),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: video.value.size.width,
        height: video.value.size.height,
        child: VideoPlayer(video),
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
    return Image(
      image: image,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => _TextBody(
        text: widget.content.textBody ?? l10n.humorEmptyFeed,
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
