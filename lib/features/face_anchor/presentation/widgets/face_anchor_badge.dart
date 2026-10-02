import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// Marks a photo the server verified as the member.
///
/// Not the account's "Verified" seal: that one says the member completed
/// identity verification. This one is about a single photo, so it uses its own
/// icon and tone and is shown only on that photo, in the member's own list.
class FaceAnchorBadge extends StatelessWidget {
  const FaceAnchorBadge({super.key, this.dense = true});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraPill(
      label: l10n.faceAnchorVerifiedShort,
      icon: MevoraIcons.faceAnchor,
      tone: MevoraTone.success,
      dense: dense,
      semanticLabel: l10n.faceAnchorVerified,
    );
  }
}
