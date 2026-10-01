import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/face_anchor/presentation/widgets/face_anchor_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_list.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The profile tab's way into photo verification.
///
/// For a member who has no verified photo — everyone who joined before Face
/// Anchor — this is an invitation, not a gate: it opens the photo list, where
/// each photo can be verified. Once a photo is verified it simply says so.
class FaceAnchorEntryTile extends StatelessWidget {
  const FaceAnchorEntryTile({super.key, required this.verified});

  /// Whether the member already has a verified Face Anchor photo.
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraListRow(
      icon: verified ? MevoraIcons.faceAnchor : MevoraIcons.faceAnchorVerify,
      iconTone: verified ? MevoraTone.success : MevoraTone.info,
      title: verified
          ? l10n.faceAnchorProfileVerifiedTitle
          : l10n.faceAnchorVerifyAction,
      subtitle: verified ? null : l10n.faceAnchorPromptTileSubtitle,
      trailing: verified ? const FaceAnchorBadge() : null,
      onTap: () => context.push(AppRoutes.editProfile),
    );
  }
}
