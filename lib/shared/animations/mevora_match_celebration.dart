import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/locale_casing.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/art/mevora_mark.dart';
import 'package:mevora/shared/widgets/mevora_avatar.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// The match moment.
///
/// Two portraits drift toward each other until they overlap — the Mevora mark
/// made of two real people — and a small lens seal lands where they meet.
/// Then the page explains *why* (the compatibility section) before it asks
/// the user to say hello. No confetti, no flashing: the overlap is the story.
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

  /// Called after the intro motion finishes (does not auto-dismiss).
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.match,
  );
  late final Animation<double> _approach = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.5, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _seal = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.38, 0.62, curve: AppCurves.emphasized),
  );
  late final Animation<double> _copy = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 1, curve: AppCurves.enter),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      widget.onCompleted?.call();
    } else {
      unawaited(
        _controller.forward().whenComplete(() => widget.onCompleted?.call()),
      );
    }
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
    final width = MediaQuery.sizeOf(context).width;
    final portrait = (width * 0.32).clamp(104.0, 148.0);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xl,
          AppSpacing.screenPadding,
          AppSpacing.lg,
        ),
        child: Column(
          children: [
            Semantics(
              label: '${widget.leftName} · ${widget.rightName}',
              child: SizedBox(
                height: portrait + AppSpacing.md,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) => _Portraits(
                    size: portrait,
                    approach: _approach.value,
                    seal: _seal.value,
                    leftName: widget.leftName,
                    rightName: widget.rightName,
                    leftImage: widget.leftImage,
                    rightImage: widget.rightImage,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FadeTransition(
              opacity: _copy,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(_copy),
                child: Column(
                  children: [
                    Text(
                      LocaleCasing.upper(
                        l10n.itsAMatchHeadline,
                        Localizations.localeOf(context),
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.palette.match,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      header: true,
                      liveRegion: true,
                      child: Text(
                        l10n.matchCelebrationLead,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineLarge,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      l10n.matchCelebrationInsight,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: context.palette.textSecondary,
                      ),
                    ),
                    if (widget.compatibilitySection != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      widget.compatibilitySection!,
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    if (widget.onSendMessage != null)
                      MevoraButton(
                        label: l10n.startChat,
                        icon: MevoraIcons.message,
                        size: MevoraButtonSize.large,
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
                      const SizedBox(height: AppSpacing.xs),
                      MevoraButton(
                        label: l10n.keepSwiping,
                        variant: MevoraButtonVariant.ghost,
                        onPressed: widget.onKeepExploring,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Portraits extends StatelessWidget {
  const _Portraits({
    required this.size,
    required this.approach,
    required this.seal,
    required this.leftName,
    required this.rightName,
    required this.leftImage,
    required this.rightImage,
  });

  final double size;
  final double approach;
  final double seal;
  final String leftName;
  final String rightName;
  final ImageProvider? leftImage;
  final ImageProvider? rightImage;

  @override
  Widget build(BuildContext context) {
    // Start a full portrait apart; rest overlapping by ~26% of a portrait.
    final restingOffset = size * 0.37;
    final startOffset = size * 1.1;
    final offset = startOffset + (restingOffset - startOffset) * approach;
    final tilt = 0.06 * (1 - approach);
    final sealSize = size * 0.34;

    Widget portrait(String name, ImageProvider? image, double angle) =>
        Transform.rotate(
          angle: angle,
          child: MevoraAvatar(
            name: name,
            image: image,
            size: size,
            ring: true,
            semanticLabel: '',
          ),
        );

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Transform.translate(
          offset: Offset(-offset, 0),
          child: portrait(leftName, leftImage, -tilt),
        ),
        Transform.translate(
          offset: Offset(offset, 0),
          child: portrait(rightName, rightImage, tilt),
        ),
        if (seal > 0)
          Positioned(
            bottom: 0,
            child: Transform.scale(
              scale: seal,
              child: Container(
                width: sealSize,
                height: sealSize,
                decoration: BoxDecoration(
                  color: context.palette.surface,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.ink.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: EdgeInsets.all(sealSize * 0.18),
                child: const MevoraMark(),
              ),
            ),
          ),
      ],
    );
  }
}
