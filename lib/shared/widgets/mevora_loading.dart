import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';

enum MevoraLoadingStyle { inline, page }

class MevoraLoading extends StatelessWidget {
  const MevoraLoading({
    super.key,
    this.message,
    this.style = MevoraLoadingStyle.inline,
    this.size = 28,
  });

  const MevoraLoading.page({super.key, this.message, this.size = 32})
    : style = MevoraLoadingStyle.page;

  final String? message;
  final MevoraLoadingStyle style;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final resolved = message ?? l10n?.loading ?? 'Loading';
    final indicator = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MevoraRiveAnimation(
          asset: MevoraRiveAssets.loading,
          width: size,
          height: size,
          semanticsLabel: resolved,
          fallback: SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
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

    if (style == MevoraLoadingStyle.page) {
      return Semantics(
        label: resolved,
        child: Center(child: indicator),
      );
    }

    return Semantics(label: resolved, child: indicator);
  }
}
