import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Match moment: portraits meet, then copy and actions stay on screen.
class MevoraMatchCelebration extends StatefulWidget {
  const MevoraMatchCelebration({
    super.key,
    required this.leftName,
    required this.rightName,
    this.leftImage,
    this.rightImage,
    this.onCompleted,
    this.onSendMessage,
    this.onKeepExploring,
  });

  final String leftName;
  final String rightName;
  final ImageProvider? leftImage;
  final ImageProvider? rightImage;
  final VoidCallback? onCompleted;
  final VoidCallback? onSendMessage;
  final VoidCallback? onKeepExploring;

  @override
  State<MevoraMatchCelebration> createState() => _MevoraMatchCelebrationState();
}

class _MevoraMatchCelebrationState extends State<MevoraMatchCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _approach;
  late final Animation<double> _labelOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.match,
    );
    _approach = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
    );
    _labelOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
    );
    unawaited(_controller.forward());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final gap = 48 - (_approach.value * 20);
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              MevoraRiveAnimation(
                asset: MevoraRiveAssets.match,
                width: 260,
                height: 200,
                fit: BoxFit.contain,
                semanticsLabel: l10n.itsAMatchHeadline,
                fallback: Icon(
                  Icons.favorite_rounded,
                  size: 88,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  MevoraAvatar(
                    name: widget.leftName,
                    image: widget.leftImage,
                    size: 88,
                  ),
                  SizedBox(width: gap),
                  MevoraAvatar(
                    name: widget.rightName,
                    image: widget.rightImage,
                    size: 88,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Opacity(
                opacity: _labelOpacity.value,
                child: Column(
                  children: [
                    Text(
                      l10n.itsAMatchHeadline,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        letterSpacing: 1.2,
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.itsAMatch,
                      style: theme.textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.youLikedEachOther,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (widget.onSendMessage != null)
                MevoraButton(
                  label: l10n.sendMessage,
                  onPressed: widget.onSendMessage,
                ),
              if (widget.onKeepExploring != null) ...[
                const SizedBox(height: AppSpacing.sm),
                MevoraButton(
                  label: l10n.keepSwiping,
                  variant: MevoraButtonVariant.ghost,
                  onPressed: widget.onKeepExploring,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
