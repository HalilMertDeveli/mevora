import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/features/match_score/domain/entities/match_score.dart';
import 'package:mevora/features/match_score/domain/repositories/match_score_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

class MatchScoreTile extends StatelessWidget {
  const MatchScoreTile({
    super.key,
    required this.uid,
    required this.repository,
  });

  final String uid;
  final MatchScoreRepository repository;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return StreamBuilder<MatchScoreSnapshot>(
      stream: repository.watchScore(uid),
      builder: (context, snapshot) {
        final score = snapshot.data?.score;
        return MevoraListRow(
          icon: MevoraIcons.liked,
          iconTone: MevoraTone.match,
          title: l10n.matchScoreTitle,
          subtitle: score == null
              ? l10n.matchScoreSubtitle
              : l10n.matchScoreValue(score),
          onTap: () => unawaited(
            showMatchScoreHistorySheet(
              context,
              uid: uid,
              repository: repository,
            ),
          ),
        );
      },
    );
  }
}

Future<void> showMatchScoreHistorySheet(
  BuildContext context, {
  required String uid,
  required MatchScoreRepository repository,
}) {
  final l10n = AppLocalizations.of(context);
  return MevoraBottomSheet.show<void>(
    context,
    title: l10n.matchScoreHistoryTitle,
    child: StreamBuilder<List<MatchScoreHistoryEntry>>(
      stream: repository.watchHistory(uid),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MatchScoreHistoryEntry>[];
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: MevoraEmptyState(
              art: MevoraArt.emptyLikes,
              compact: true,
              message: l10n.matchScoreHistoryEmpty,
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final entry = items[index];
            final label = entry.type == MatchScoreHistoryType.newMatch
                ? l10n.matchScoreHistoryMatch
                : l10n.matchScoreHistoryInteraction;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: MevoraPill(
                label: '+${entry.delta}',
                tone: MevoraTone.match,
              ),
              title: Text(label),
              trailing: Text(
                L10nFormat.compactDate(l10n, entry.createdAt),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            );
          },
        );
      },
    ),
  );
}
