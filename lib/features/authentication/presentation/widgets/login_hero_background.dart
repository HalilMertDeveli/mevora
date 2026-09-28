import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_colors.dart';

/// The auth backdrop: the linen page, nothing else. The welcome screen's
/// only image is the Mevora mark — no stock couple, no gradient wash.
class LoginHeroBackground extends StatelessWidget {
  const LoginHeroBackground({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.palette.background,
      child: child ?? const SizedBox.expand(),
    );
  }
}
