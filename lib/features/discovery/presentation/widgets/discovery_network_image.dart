import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/shared/animations/mevora_photo_fade.dart';

/// Discovery image with loading and error placeholders.
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
    if (_prefetched.contains(url) || url.startsWith('mock://')) {
      return;
    }
    _prefetched.add(url);
    final provider = NetworkImage(url);
    provider.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((_, _) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('mock://')) {
      return _MockIllustration(url: url);
    }
    final theme = Theme.of(context);
    return MevoraPhotoFade(
      photoKey: url,
      child: Image.network(
        url,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) {
            return child;
          }
          return _LoadingPlaceholder(color: theme.colorScheme.primary);
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
          return _LoadingPlaceholder(color: theme.colorScheme.primary);
        },
      ),
    );
  }
}

class _MockIllustration extends StatelessWidget {
  const _MockIllustration({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = url.replaceFirst('mock://', '').split('/');
    final variant = parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0;
    final palette = [
      theme.colorScheme.primaryContainer,
      theme.colorScheme.secondaryContainer,
      theme.colorScheme.tertiaryContainer,
    ];
    final color = palette[variant % palette.length];
    return ColoredBox(
      color: color,
      child: Center(
        child: Icon(
          Icons.face_retouching_natural_outlined,
          size: 88,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
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
    return ColoredBox(
      color: color,
      child: Icon(Icons.image_not_supported_outlined, size: 48, color: iconColor),
    );
  }
}
