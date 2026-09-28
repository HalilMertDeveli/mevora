import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// "Boosted" marker on a profile photo.
class DiscoveryBoostBadge extends StatelessWidget {
  const DiscoveryBoostBadge({
    super.key,
    this.compact = true,
    this.onMedia = true,
  });

  final bool compact;

  /// White-on-scrim over a photo; ember tint on the page.
  final bool onMedia;

  @override
  Widget build(BuildContext context) {
    return MevoraPill(
      label: AppLocalizations.of(context).boostDiscoverBadge,
      icon: MevoraIcons.boostActive,
      tone: onMedia ? MevoraTone.onMedia : MevoraTone.accent,
      dense: compact,
    );
  }
}
