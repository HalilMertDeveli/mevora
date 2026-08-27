import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/features/humor/presentation/widgets/humor_compatibility_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Optional match-screen badge (MVP: file exists; not wired into match UI yet).
class HumorCompatibilityBadge extends StatelessWidget {
  const HumorCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
    this.strongestShared = const [],
    this.onTap,
  });

  final int score;
  final bool compact;
  final List<String> strongestShared;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap ??
          () {
            unawaited(
              HumorCompatibilitySheet.show(
                context,
                score: score,
                strongestShared: strongestShared,
              ),
            );
          },
      child: MevoraChip(
        label: compact
            ? '${l10n.humorCompatibilityTitle} · $score%'
            : l10n.humorCompatibilityTitle,
        selected: score >= 60,
        compact: compact,
      ),
    );
  }
}
