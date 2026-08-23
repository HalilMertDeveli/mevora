import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
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
  final Widget? compatibilitySection;

  @override
  State<MevoraMatchCelebration> createState() => _MevoraMatchCelebrationState();
}

class _MevoraMatchCelebrationState extends State<MevoraMatchCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _approach;
  late final Animation<double> _labelOpacity;
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
      curve: const Interval(0.5, 1, curve: Curves.easeOut),
    );
    // Defer Rive decode one frame so first paint stays responsive.
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
      Icons.favorite_rounded,
      size: (riveSize * 0.45).clamp(28, 48),
      color: theme.colorScheme.primary,
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
                    semanticsLabel: l10n.itsAMatchHeadline,
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
                      if (widget.compatibilitySection != null) ...[
                        const SizedBox(height: AppSpacing.lg),
                        widget.compatibilitySection!,
                      ],
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
      ),
    );
  }
}
