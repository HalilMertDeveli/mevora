import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/animations/mevora_photo_fade.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/images/mevora_photo_images.dart';

/// Discovery image with calm loading and error placeholders. No blur overlay.
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
    listener = ImageStreamListener(
      (_, _) => stream.removeListener(listener),
      onError: (_, _) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
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
            errorBuilder: (context, error, stackTrace) =>
                const PhotoUnavailablePlaceholder(),
          ),
        ),
      );
    }
    final provider = MevoraNetworkImages.provider(url);
    if (provider == null) {
      return const PhotoUnavailablePlaceholder();
    }
    return SizedBox.expand(
      // Storage photos resolve to the disk-cached provider, so a card seen
      // before an app restart is not downloaded again.
      child: Image(
        image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
        fit: fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return const PhotoLoadingPlaceholder();
        },
        errorBuilder: (context, error, stackTrace) =>
            const PhotoUnavailablePlaceholder(),
      ),
    );
  }
}

/// A photo that is still arriving: the sand surface, nothing spinning.
class PhotoLoadingPlaceholder extends StatelessWidget {
  const PhotoLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(color: context.palette.surfaceMuted),
    );
  }
}

/// A photo that could not load. Quiet — the person, not the failure, should
/// remain the subject of the card.
class PhotoUnavailablePlaceholder extends StatelessWidget {
  const PhotoUnavailablePlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    // Deep ink rather than sand: the card's name and scrim are drawn for a
    // photograph, and a dark field keeps them legible when there is none.
    return const SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.ink80, AppColors.ink],
          ),
        ),
        child: Center(
          child: Icon(MevoraIcons.photo, size: 40, color: AppColors.ink60),
        ),
      ),
    );
  }
}
