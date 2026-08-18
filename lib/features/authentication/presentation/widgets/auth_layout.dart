import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/shared/components/mevora_logo.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            const SizedBox(height: AppSpacing.lg),
            const MevoraLogo(size: 56),
            const SizedBox(height: AppSpacing.xl),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            MevoraCard(child: child),
          ],
        ),
      ),
    );
  }
}
