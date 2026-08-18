import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/constants/app_strings.dart';

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
    final indicator = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(message!, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );

    if (style == MevoraLoadingStyle.page) {
      return Semantics(
        label: message ?? AppStrings.loading,
        child: Center(child: indicator),
      );
    }

    return Semantics(label: message ?? AppStrings.loading, child: indicator);
  }
}
