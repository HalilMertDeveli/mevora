import 'package:flutter/material.dart';
import 'package:mevora/features/music/domain/services/music_compatibility.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

class MusicCompatibilityBadge extends StatelessWidget {
  const MusicCompatibilityBadge({
    super.key,
    required this.score,
    this.compact = true,
  });

  final int score;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraChip(
      label: compact
          ? l10n.musicCompatibilityShort(score)
          : l10n.musicCompatibilityPercent(score),
      selected: MusicCompatibilityCalculator.band(score) !=
          MusicCompatibilityBand.low,
      compact: compact,
    );
  }
}
