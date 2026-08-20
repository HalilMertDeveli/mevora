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
        filterQuality: FilterQuality.high,
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
    final parts = url.replaceFirst('mock://', '').split('/');
    final seed = parts.isEmpty ? 'mevora' : parts.first;
    final variant = parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0;
    const palettes = [
      [Color(0xFF3D1844), Color(0xFF5C2E62), Color(0xFFD4A8DC)],
      [Color(0xFF3B2410), Color(0xFFC47B3A), Color(0xFFF6E1CC)],
      [Color(0xFF083828), Color(0xFF2F6F56), Color(0xFF7FCBAD)],
    ];
    final colors = palettes[variant % palettes.length];
    final initial = seed.replaceAll('mock-', '').isEmpty
        ? 'M'
        : seed.replaceAll('mock-', '')[0].toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Icon(
                Icons.auto_awesome,
                size: 48,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Center(
            child: Text(
              initial,
              style: Theme.of(context).textTheme.displayLarge?.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
