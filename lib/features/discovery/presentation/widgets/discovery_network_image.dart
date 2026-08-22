import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_photo_fade.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Discovery image with loading and error placeholders. No blur overlay.
class DiscoveryNetworkImage extends StatelessWidget {
  const DiscoveryNetworkImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
  });

  final String url;
  final BoxFit fit;

  static final Set<String> _prefetched = <String>{};

  static void prefetch(String url) {
    if (_prefetched.contains(url) || !MevoraNetworkImages.isHttpUrl(url)) {
      return;
    }
    _prefetched.add(url);
    final provider = MevoraNetworkImages.provider(url);
    if (provider == null) {
      return;
    }
    provider
        .resolve(const ImageConfiguration())
        .addListener(ImageStreamListener((_, _) {}));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final asset = MevoraPhotoImages.assetPath(url);
    if (asset != null) {
      return MevoraPhotoFade(
        photoKey: asset,
        child: SizedBox.expand(
          child: Image.asset(
            asset,
            fit: fit,
            filterQuality: FilterQuality.high,
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
      return _ErrorPlaceholder(
        color: theme.colorScheme.primaryContainer,
        iconColor: theme.colorScheme.onPrimaryContainer,
      );
    }
    return MevoraPhotoFade(
      photoKey: url,
      child: SizedBox.expand(
        child: Image.network(
          url,
          fit: fit,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }
            return const _LoadingPlaceholder();
          },
          errorBuilder: (context, error, stackTrace) => _ErrorPlaceholder(
            color: theme.colorScheme.primaryContainer,
            iconColor: theme.colorScheme.onPrimaryContainer,
          ),
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return AnimatedOpacity(
                opacity: 1,
                duration: AppDurations.photo,
                child: child,
              );
            }
            return const _LoadingPlaceholder();
          },
        ),
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
