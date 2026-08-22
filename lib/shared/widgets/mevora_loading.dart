import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';

enum MevoraLoadingStyle { inline, page }

class MevoraLoading extends StatelessWidget {
  const MevoraLoading({
    super.key,
    this.message,
    this.style = MevoraLoadingStyle.inline,
    this.size,
    this.asset,
  });

  const MevoraLoading.page({
    super.key,
    this.message,
    this.size,
    this.asset,
  }) : style = MevoraLoadingStyle.page;

  final String? message;
  final MevoraLoadingStyle style;
  final double? size;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolved = message ?? l10n?.loading ?? 'Loading';
    final resolvedSize =
        size ??
        (style == MevoraLoadingStyle.page
            ? MevoraMotionSize.loading(context)
            : MevoraMotionSize.inline(context));
    final fallbackSize = (resolvedSize * 0.42).clamp(20.0, 36.0);
    final indicator = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MevoraRiveAnimation(
          asset: asset ?? MevoraRiveAssets.loading,
          width: resolvedSize,
          height: resolvedSize,
          semanticsLabel: resolved,
          fallback: SizedBox(
            width: fallbackSize,
            height: fallbackSize,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            message!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ],
    );

    if (style == MevoraLoadingStyle.page) {
      return Semantics(
        label: resolved,
        child: Center(child: indicator),
      );
    }

    return Semantics(label: resolved, child: indicator);
  }
}
