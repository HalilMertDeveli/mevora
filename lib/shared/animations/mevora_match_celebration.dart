import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// Match moment: connection-first celebration with optional compatibility reveal.
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
    this.onViewAnswers,
    this.compatibilitySection,
  });

  final String leftName;
  final String rightName;
  final ImageProvider? leftImage;
  final ImageProvider? rightImage;

  /// Optional callback after the intro motion finishes (does not auto-dismiss).
  final VoidCallback? onCompleted;
  final VoidCallback? onSendMessage;
  final VoidCallback? onKeepExploring;
  final VoidCallback? onViewAnswers;
  final Widget? compatibilitySection;

  @override
  State<MevoraMatchCelebration> createState() => _MevoraMatchCelebrationState();
}

class _MevoraMatchCelebrationState extends State<MevoraMatchCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _approach;
  late final Animation<double> _labelOpacity;
  late final Animation<double> _scale;
  bool _showRive = false;

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
      curve: const Interval(0.45, 1, curve: Curves.easeOut),
    );
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 1, curve: Curves.easeOutCubic),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _showRive = true);
    });
    unawaited(
      _controller.forward().whenComplete(() {
        widget.onCompleted?.call();
      }),
    );
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
    final riveSize = MevoraMotionSize.celebration(context);
    final avatarSize = MevoraMotionSize.accent(context) * 0.85;
    final riveFallback = Icon(
      Icons.insights_outlined,
      size: (riveSize * 0.45).clamp(28, 48),
      color: AppColors.softGreen,
    );

    return SafeArea(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final gap = 36 - (_approach.value * 14);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                if (_showRive)
                  MevoraRiveAnimation(
                    asset: MevoraRiveAssets.match,
                    width: riveSize,
                    height: riveSize * 0.78,
                    fit: BoxFit.contain,
                    semanticsLabel: l10n.matchCelebrationLead,
                    fallback: riveFallback,
                  )
                else
                  SizedBox(
                    width: riveSize,
                    height: riveSize * 0.78,
                    child: Center(child: riveFallback),
                  ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    MevoraAvatar(
                      name: widget.leftName,
                      image: widget.leftImage,
                      size: avatarSize,
                    ),
                    SizedBox(width: gap),
                    MevoraAvatar(
                      name: widget.rightName,
                      image: widget.rightImage,
                      size: avatarSize,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Opacity(
                  opacity: _labelOpacity.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Column(
                      children: [
                        Text(
                          l10n.matchCelebrationLead,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          l10n.itsAMatchHeadline,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: AppColors.softGreen,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          l10n.matchCelebrationInsight,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (widget.compatibilitySection != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          widget.compatibilitySection!,
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (widget.onSendMessage != null)
                  MevoraButton(
                    label: l10n.startChat,
                    onPressed: widget.onSendMessage,
                  ),
                if (widget.onViewAnswers != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  MevoraButton(
                    label: l10n.matchViewAnswers,
                    variant: MevoraButtonVariant.secondary,
                    onPressed: widget.onViewAnswers,
                  ),
                ],
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
      ),
    );
  }
}
