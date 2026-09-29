import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/art/mevora_spot.dart';

enum MevoraLoadingStyle { inline, page }

/// Waiting. The orbit loader by default; pass [art] when the wait has a
/// subject worth naming (analysing music, finding people nearby).
class MevoraLoading extends StatelessWidget {
  const MevoraLoading({
    super.key,
    this.message,
    this.style = MevoraLoadingStyle.inline,
    this.size,
    this.art,
  });

  const MevoraLoading.page({super.key, this.message, this.size, this.art})
    : style = MevoraLoadingStyle.page;

  final String? message;
  final MevoraLoadingStyle style;
  final double? size;
  final MevoraArt? art;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolved = message ?? l10n?.loading ?? 'Loading';
    final isPage = style == MevoraLoadingStyle.page;
    final visual = art != null
        ? MevoraSpot(
            art: art!,
            size: size ?? (isPage ? 112 : 72),
            animate: true,
          )
        : MevoraOrbitLoader(size: size ?? (isPage ? 56 : 36));

    final indicator = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        visual,
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );

    return Semantics(
      label: resolved,
      liveRegion: true,
      child: isPage
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: indicator,
              ),
            )
          : indicator,
    );
  }
}
