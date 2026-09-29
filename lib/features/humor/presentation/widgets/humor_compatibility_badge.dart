import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Match humor badge: a coarse "high / moderate / low" reading, never the
/// number behind it. Tapping opens [HumorCompatibilitySheet].
class HumorCompatibilityBadge extends StatelessWidget {
  const HumorCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
    this.strongestShared = const [],
    this.onTap,
  });

  /// 0–100 from the server; only used to pick the bucket.
  final int score;
  final bool compact;
  final List<HumorCategory> strongestShared;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final level = HumorCompatibility.levelOf(score);
    final label = HumorCompatibilitySheet.levelLabel(l10n, level);
    void open() {
      final tap = onTap;
      if (tap != null) {
        tap();
        return;
      }
      unawaited(
        HumorCompatibilitySheet.show(
          context,
          score: score,
          strongestShared: strongestShared,
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: open,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
          child: MevoraPill(
            label: label,
            icon: level == HumorCompatibilityLevel.high
                ? MevoraIcons.humorActive
                : MevoraIcons.humor,
            tone: level == HumorCompatibilityLevel.high
                ? MevoraTone.humor
                : MevoraTone.neutral,
            dense: compact,
          ),
        ),
      ),
    );
  }
}
