import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mevora/shared/animations/mevora_photo_fade.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Discovery image with loading and error placeholders. No blur overlay.
///
/// Real Firebase Storage photos are decoded at display size ([cacheWidth]) so
/// switching to photo 2 does not freeze the UI on full-resolution decode.
class DiscoveryNetworkImage extends StatelessWidget {
  const DiscoveryNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final String url;
  final BoxFit fit;

  static final Set<String> _prefetched = <String>{};

  static void prefetch(String url, {int? cacheWidth}) {
    if (_prefetched.contains(url) || !MevoraNetworkImages.isHttpUrl(url)) {
      return;
    }
    _prefetched.add(url);
    ImageProvider? provider = MevoraNetworkImages.provider(url);
    if (provider == null) {
      return;
    }
    if (cacheWidth != null && cacheWidth > 0) {
      provider = ResizeImage(provider, width: cacheWidth);
    }
    final stream = provider.resolve(const ImageConfiguration());
    late ImageStreamListener listener;
    listener = ImageStreamListener((_, _) {
      stream.removeListener(listener);
    }, onError: (_, _) {
      stream.removeListener(listener);
    });
    stream.addListener(listener);
  }

  // #region agent log
  static void _logDebug(
    String message, {
    String hypothesisId = 'PHOTO',
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    try {
      final entry = <String, Object?>{
        'sessionId': '80971b',
        'runId': 'post-fix',
        'hypothesisId': hypothesisId,
        'location': 'discovery_network_image.dart',
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      // ignore: avoid_print
      print('[PHOTO_DEBUG] ${jsonEncode(entry)}');
    } on Object {
      // Ignore logging failures.
    }
  }
  // #endregion

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.sizeOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Cap decode size so multi-MB Storage photos stay off the UI thread.
    // Keep under ~1080px — pending discovery JPGs are often full camera size.
    final cacheWidth = (media.width * dpr).round().clamp(320, 1080);

    final asset = MevoraPhotoImages.assetPath(url);
    if (asset != null) {
      return MevoraPhotoFade(
        photoKey: asset,
        child: SizedBox.expand(
          child: Image.asset(
            asset,
            fit: fit,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => _ErrorPlaceholder(
              color: theme.colorScheme.primaryContainer,
              iconColor: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
      );
    }
    if (!MevoraNetworkImages.isHttpUrl(url)) {
      // #region agent log
      _logDebug(
        'non_http_url',
        hypothesisId: 'H4',
        data: <String, Object?>{
          'scheme': Uri.tryParse(url)?.scheme,
          'urlLen': url.length,
        },
      );
      // #endregion
      return _ErrorPlaceholder(
        color: theme.colorScheme.primaryContainer,
        iconColor: theme.colorScheme.onPrimaryContainer,
      );
    }
    // #region agent log
    final loadStartedAt = DateTime.now().millisecondsSinceEpoch;
    _logDebug(
      'network_image_build',
      hypothesisId: 'H1',
      data: <String, Object?>{
        'cacheWidth': cacheWidth,
        'urlLen': url.length,
        'host': Uri.tryParse(url)?.host,
      },
    );
    // #endregion
    return SizedBox.expand(
      child: Image.network(
        url,
        fit: fit,
        cacheWidth: cacheWidth,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            // #region agent log
            _logDebug(
              'network_image_loaded',
              hypothesisId: 'H1',
              data: <String, Object?>{
                'elapsedMs':
                    DateTime.now().millisecondsSinceEpoch - loadStartedAt,
                'cacheWidth': cacheWidth,
              },
            );
            // #endregion
            return child;
          }
          return const _LoadingPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) {
          // #region agent log
          _logDebug(
            'network_image_error',
            hypothesisId: 'H4',
            data: <String, Object?>{
              'error': error.toString(),
              'urlLen': url.length,
            },
          );
          // #endregion
          return _ErrorPlaceholder(
            color: theme.colorScheme.primaryContainer,
            iconColor: theme.colorScheme.onPrimaryContainer,
          );
        },
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.color, required this.iconColor});

  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: color,
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 48,
          color: iconColor,
        ),
      ),
    );
  }
}
