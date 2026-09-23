import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/boost/domain/entities/boost.dart';
import 'package:mevora/features/boost/domain/entities/boost_results.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Shows what a Boost actually delivered.
///
/// Numbers come from the backend and are reported as they are. A Boost that
/// reached nobody shows zeroes — never a softened or invented success state,
/// and never a comparison percentage, because no visibility baseline is
/// measured yet to compare against.
class BoostResultsPanel extends StatelessWidget {
  const BoostResultsPanel({
    super.key,
    required this.boost,
    this.now,
  });

  final Boost? boost;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final current = boost;
    final l10n = AppLocalizations.of(context);
    if (current == null) {
      return const SizedBox.shrink();
    }
    final isActive = current.isActiveAt(now ?? DateTime.now());
    final results = current.results;

    // Counters only start existing once the backend has observed something,
    // so an active Boost with nothing yet says so rather than showing zeroes
    // as if they were final.
    if (isActive && results.isEmpty) {
      return _Card(
        title: l10n.boostResultsTitle,
        children: [
          Text(
            l10n.boostResultsPending,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    return _Card(
      title: isActive ? l10n.boostResultsTitle : l10n.boostCompletedTitle,
      children: [
        if (!isActive && results.isEmpty)
          Text(
            l10n.boostCompletedEmpty,
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else ...[
          _MetricRow(
            icon: Icons.visibility_outlined,
            label: l10n.boostReachedPeople(results.uniqueUsersReached),
          ),
          const SizedBox(height: AppSpacing.xs),
          _MetricRow(
            icon: Icons.favorite_outline,
            label: l10n.boostLikesReceived(results.likesReceived),
          ),
          const SizedBox(height: AppSpacing.xs),
          _MetricRow(
            icon: Icons.people_outline,
            label: l10n.boostMatchesCreated(results.matchesCreated),
          ),
        ],
        if (isActive) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.boostResultsDelayNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
