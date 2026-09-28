import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_meter.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The dimensions Mevora compares two people on. Each has one glyph and one
/// tone, so "music" reads as music wherever it appears.
enum CompatibilitySignalKind {
  relationship,
  personalValues,
  questions,
  lifestyle,
  interests,
  hobbies,
  music,
  humor,
  communication,
  languages,
}

extension CompatibilitySignalKindX on CompatibilitySignalKind {
  IconData get icon => switch (this) {
    CompatibilitySignalKind.relationship => MevoraIcons.like,
    CompatibilitySignalKind.personalValues => MevoraIcons.compatibility,
    CompatibilitySignalKind.questions => MevoraIcons.questions,
    CompatibilitySignalKind.lifestyle => MevoraIcons.coffee,
    CompatibilitySignalKind.interests => MevoraIcons.insight,
    CompatibilitySignalKind.hobbies => MevoraIcons.art,
    CompatibilitySignalKind.music => MevoraIcons.track,
    CompatibilitySignalKind.humor => MevoraIcons.humor,
    CompatibilitySignalKind.communication => MevoraIcons.message,
    CompatibilitySignalKind.languages => MevoraIcons.books,
  };

  MevoraTone get tone => switch (this) {
    CompatibilitySignalKind.music => MevoraTone.music,
    CompatibilitySignalKind.humor => MevoraTone.humor,
    CompatibilitySignalKind.relationship ||
    CompatibilitySignalKind.personalValues ||
    CompatibilitySignalKind.questions => MevoraTone.compatibility,
    _ => MevoraTone.accent,
  };

  String label(AppLocalizations l10n) => switch (this) {
    CompatibilitySignalKind.relationship => l10n.compatCategoryRelationship,
    CompatibilitySignalKind.personalValues => l10n.compatCategoryValues,
    CompatibilitySignalKind.questions => l10n.compatCategoryQuestions,
    CompatibilitySignalKind.lifestyle => l10n.compatCategoryLifestyle,
    CompatibilitySignalKind.interests => l10n.compatCategoryInterests,
    CompatibilitySignalKind.hobbies => l10n.compatCategoryHobbies,
    CompatibilitySignalKind.music => l10n.compatCategoryMusic,
    CompatibilitySignalKind.humor => l10n.humorLabTitle,
    CompatibilitySignalKind.communication => l10n.compatCategoryCommunication,
    CompatibilitySignalKind.languages => l10n.compatCategoryLanguages,
  };
}

typedef CompatibilitySignal = ({CompatibilitySignalKind kind, int score});

/// Keeps the scored signals, strongest first.
List<CompatibilitySignal> rankSignals(
  Map<CompatibilitySignalKind, int?> scores, {
  int? limit,
}) {
  final list = <CompatibilitySignal>[
    for (final e in scores.entries)
      if (e.value != null && e.value! > 0) (kind: e.key, score: e.value!),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return limit == null ? list : list.take(limit).toList();
}

/// The overall score as a quiet ring — the number is there for people who
/// want it, but it never shouts over the person.
class CompatibilityRing extends StatelessWidget {
  const CompatibilityRing({
    super.key,
    required this.score,
    this.size = 48,
    this.onMedia = false,
    this.animate = true,
  });

  final int score;
  final double size;
  final bool onMedia;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final track = onMedia
        ? AppColors.mediaControlBorder
        : p.compatibilityContainer;
    final arc = onMedia ? AppColors.onMedia : p.compatibility;
    final text = onMedia ? AppColors.onMedia : p.onCompatibilityContainer;
    final target = score.clamp(0, 100) / 100;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Semantics(
      label: l10n.compatScoreHeading,
      value: '$score%',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: animate && !reduce ? 0 : target, end: target),
          duration: AppDurations.slow,
          curve: AppCurves.enter,
          builder: (context, v, _) => CustomPaint(
            painter: _RingPainter(value: v, track: track, arc: arc),
            child: Center(
              child: Text(
                '$score',
                style: TextStyle(
                  fontFamily: AppTypography.displayFontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: size * 0.36,
                  height: 1,
                  color: text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.track, required this.arc});

  final double value;
  final Color track;
  final Color arc;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.shortestSide * 0.09;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    if (value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * value,
        false,
        Paint()
          ..color = arc
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.arc != arc || old.track != track;
}

/// Signals as small tone pills: "♪ Music 82".
class CompatibilitySignalPills extends StatelessWidget {
  const CompatibilitySignalPills({
    super.key,
    required this.signals,
    this.showScores = true,
  });

  final List<CompatibilitySignal> signals;
  final bool showScores;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: AppSpacing.xs + AppSpacing.xxs,
      runSpacing: AppSpacing.xs + AppSpacing.xxs,
      children: [
        for (final s in signals)
          MevoraPill(
            icon: s.kind.icon,
            tone: s.kind.tone,
            label: showScores
                ? '${s.kind.label(l10n)} · ${s.score}'
                : s.kind.label(l10n),
            semanticLabel: '${s.kind.label(l10n)}: ${s.score}%',
          ),
      ],
    );
  }
}

/// One signal as a labelled meter — used in the full "why you fit" reveal.
class CompatibilitySignalBar extends StatelessWidget {
  const CompatibilitySignalBar({super.key, required this.signal});

  final CompatibilitySignal signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final c = mevoraToneColors(context, signal.kind.tone);
    final label = signal.kind.label(l10n);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      child: Row(
        children: [
          Icon(signal.kind.icon, size: 18, color: c.strong),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            flex: 5,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: context.palette.textPrimary,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 6,
            child: MevoraMeter(
              value: signal.score / 100,
              tone: signal.kind.tone,
              semanticLabel: label,
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '${signal.score}',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                color: context.palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
