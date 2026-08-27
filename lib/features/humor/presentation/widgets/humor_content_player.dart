import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';

/// Renders a single humor item (text / meme / image). Video is a placeholder.
class HumorContentPlayer extends StatelessWidget {
  const HumorContentPlayer({
    super.key,
    required this.content,
    this.replayToken = 0,
  });

  final HumorContent content;
  final int replayToken;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final image = MevoraNetworkImages.provider(
      content.downloadUrl ?? content.thumbUrl,
    );

    return KeyedSubtree(
      key: ValueKey('${content.contentId}-$replayToken'),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              Image(
                image: image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _TextBody(
                  text: content.textBody ?? l10n.humorEmptyFeed,
                ),
              )
            else
              _TextBody(text: content.textBody ?? l10n.humorEmptyFeed),
            Positioned(
              left: AppSpacing.md,
              top: AppSpacing.md,
              child: DecoratedBox(
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
                    content.category.apiValue,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            ),
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
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
