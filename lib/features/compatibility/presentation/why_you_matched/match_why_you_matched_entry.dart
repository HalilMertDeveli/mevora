import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/compatibility_scope.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_edge_case_handler.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_sheet.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Chat match screen entry for server-backed Why You Matched reasons.
///
/// Fetches via [getWhyYouMatched] on tap — never invents copy or scores.
class MatchWhyYouMatchedEntry extends StatefulWidget {
  const MatchWhyYouMatchedEntry({
    super.key,
    required this.matchId,
    this.analytics,
  });

  final String matchId;
  final AnalyticsProvider? analytics;

  @override
  State<MatchWhyYouMatchedEntry> createState() =>
      _MatchWhyYouMatchedEntryState();
}

class _MatchWhyYouMatchedEntryState extends State<MatchWhyYouMatchedEntry> {
  var _fetching = false;

  Future<void> _open({bool forceRefresh = false}) async {
    if (_fetching) {
      return;
    }
    final repo = CompatibilityScope.maybeOf(context);
    if (repo == null) {
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() => _fetching = true);
    unawaited(
      widget.analytics?.logEvent(
        AnalyticsEvents.whyYouMatchOpened,
        parameters: {'match_id_present': widget.matchId.isNotEmpty},
      ),
    );
    final result = await repo.fetchForMatch(
      matchId: widget.matchId,
      forceRefresh: forceRefresh,
    );
    if (!mounted) {
      return;
    }
    setState(() => _fetching = false);
    final viewModel = WhyYouMatchedEdgeCaseHandler.fromFetchResult(l10n, result);
    await showWhyYouMatchedSheet(
      context,
      status: viewModel.status,
      result: viewModel.result,
      message: viewModel.message,
      onRetry: () => unawaited(_open(forceRefresh: true)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (CompatibilityScope.maybeOf(context) == null) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.favorite_outline),
        title: Text(l10n.whyYouMatch),
        trailing: _fetching
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: _fetching ? null : () => unawaited(_open()),
      ),
    );
  }
}
