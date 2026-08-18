import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/app_config.dart';
import 'package:mevora/core/constants/app_constants.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/shared/components/mevora_logo.dart';
import 'package:mevora/shared/widgets/mevora_widgets.dart';

class DesignSystemPage extends StatefulWidget {
  const DesignSystemPage({super.key, required this.config});

  final AppConfig config;

  @override
  State<DesignSystemPage> createState() => _DesignSystemPageState();
}

class _DesignSystemPageState extends State<DesignSystemPage> {
  bool _travelSelected = true;
  bool _fitnessSelected = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          children: [
            const MevoraLogo(),
            const SizedBox(height: AppSpacing.md),
            Text(
              AppConstants.tagline,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: MevoraChip(
                label: widget.config.appName,
                selected: true,
                onSelected: (_) {},
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            MevoraCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const MevoraAvatar(name: 'Mevora User', isVerified: true),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Design system',
                              style: theme.textTheme.titleLarge,
                            ),
                            Text(
                              'Reusable components for every screen.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const MevoraTextField(
                    label: 'Example field',
                    hint: 'Type something',
                    prefixIcon: Icons.favorite_outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      MevoraChip(
                        label: 'Travel',
                        selected: _travelSelected,
                        onSelected: (value) {
                          setState(() => _travelSelected = value);
                        },
                      ),
                      MevoraChip(
                        label: 'Fitness',
                        selected: _fitnessSelected,
                        onSelected: (value) {
                          setState(() => _fitnessSelected = value);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            MevoraButton(
              label: 'Primary action',
              onPressed: () {
                unawaited(
                  MevoraDialog.show(
                    context,
                    title: 'Mevora',
                    message: 'Dialogs use the shared design system.',
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            MevoraButton(
              label: 'Open sheet',
              variant: MevoraButtonVariant.secondary,
              onPressed: () {
                unawaited(
                  MevoraBottomSheet.show<void>(
                    context,
                    title: 'Bottom sheet',
                    child: const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        'Sheets, dialogs, and cards share one visual language.',
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: const MevoraLoading(message: 'Preparing Mevora'),
            ),
            const SizedBox(height: AppSpacing.lg),
            const MevoraEmptyState(
              title: 'Architecture ready',
              message:
                  'Phase 1 established the project structure, theme, routing, and shared components.',
            ),
            const SizedBox(height: AppSpacing.lg),
            const MevoraErrorView(
              title: 'Error state',
              message: 'Failures should use this view instead of ad-hoc text.',
            ),
          ],
        ),
      ),
    );
  }
}
