import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/face_anchor/presentation/face_anchor_l10n.dart';
import 'package:mevora/features/face_anchor/presentation/widgets/face_anchor_badge.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/art/mevora_spot.dart';
import 'package:mevora/shared/widgets/mevora_card.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class OnboardingPhotoGrid extends StatelessWidget {
  const OnboardingPhotoGrid({
    super.key,
    required this.drafts,
    required this.enabled,
    required this.onAddCamera,
    required this.onAddGallery,
    required this.onRetry,
    required this.onRemove,
    required this.onReorder,
    this.faceAnchorStatusOf,
    this.onVerify,
    this.needsFaceAnchor = false,
  });

  /// How each uploaded photo stands with Face Anchor verification. Null where
  /// verification is not wired in; the grid then looks as it always did.
  final FaceAnchorPhotoStatus Function(OnboardingPhotoDraft draft)?
  faceAnchorStatusOf;

  /// Opens verification for a photo.
  final ValueChanged<OnboardingPhotoDraft>? onVerify;

  /// The member has enough photos but must still verify one to continue.
  final bool needsFaceAnchor;

  final List<OnboardingPhotoDraft> drafts;
  final bool enabled;
  final VoidCallback onAddCamera;
  final VoidCallback onAddGallery;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onRemove;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final canAdd = drafts.length < OnboardingConfig.maxPhotos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.onboardingPhotosHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: MevoraCard(
              emphasis: MevoraCardEmphasis.outline,
              child: MevoraEmptyState(
                art: MevoraArt.photos,
                compact: true,
                title: l10n.addPhotoGallery,
                message: l10n.photoEmptyHint,
              ),
            ),
          ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: drafts.length,
          onReorder: onReorder,
          itemBuilder: (context, index) {
            final draft = drafts[index];
            return _PhotoTile(
              key: ValueKey(draft.id),
              draft: draft,
              index: index,
              enabled: enabled,
              faceAnchor:
                  faceAnchorStatusOf?.call(draft) ?? FaceAnchorPhotoStatus.none,
              onVerify: onVerify == null ? null : () => onVerify!(draft),
              onRetry: () => onRetry(draft.id),
              onRemove: () => onRemove(draft.id),
            );
          },
        ),
        if (drafts.length < OnboardingConfig.minPhotos) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.photoMinRequired,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.palette.warning,
            ),
          ),
        ] else if (needsFaceAnchor) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.faceAnchorRequiredNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: context.palette.warning,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (canAdd) ...[
          MevoraButton(
            label: l10n.addPhotoCamera,
            icon: MevoraIcons.camera,
            onPressed: enabled ? onAddCamera : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: l10n.addPhotoGallery,
            icon: MevoraIcons.photos,
            variant: MevoraButtonVariant.secondary,
            onPressed: enabled ? onAddGallery : null,
          ),
        ],
      ],
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    super.key,
    required this.draft,
    required this.index,
    required this.enabled,
    required this.faceAnchor,
    required this.onVerify,
    required this.onRetry,
    required this.onRemove,
  });

  final OnboardingPhotoDraft draft;
  final int index;
  final bool enabled;
  final FaceAnchorPhotoStatus faceAnchor;
  final VoidCallback? onVerify;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent = (draft.progress * 100).round();
    final settled = draft.remote != null && !draft.isUploading;
    final canVerify =
        settled &&
        onVerify != null &&
        (faceAnchor == FaceAnchorPhotoStatus.canVerify ||
            faceAnchor == FaceAnchorPhotoStatus.notVerified);
    ImageProvider? image;
    final bytes = draft.localBytes;
    if (bytes != null && bytes.isNotEmpty) {
      image = MemoryImage(Uint8List.fromList(bytes));
    } else if (MevoraNetworkImages.isHttpUrl(draft.remote?.downloadUrl)) {
      image = MevoraNetworkImages.provider(draft.remote!.downloadUrl);
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (image != null)
                Image(image: image, fit: BoxFit.cover)
              else
                ColoredBox(
                  color: theme.colorScheme.surfaceContainerHigh,
                  child: const Icon(MevoraIcons.profile),
                ),
              if (draft.isUploading)
                ColoredBox(
                  color: AppColors.scrim.withValues(alpha: 0.5),
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context).percentValue(percent),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppColors.onMedia,
                      ),
                    ),
                  ),
                ),
              if (draft.error != null && !draft.isUploading)
                ColoredBox(
                  color: AppColors.scrim.withValues(alpha: 0.5),
                  child: const Icon(
                    MevoraIcons.error,
                    size: 20,
                    color: AppColors.onMedia,
                  ),
                ),
              if (draft.remote != null && !draft.isUploading)
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xs),
                    child: Icon(
                      MevoraIcons.success,
                      size: 16,
                      color: AppColors.onMedia,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Text(
        index == 0
            ? l10n.onboardingPrimaryPhoto
            : l10n.onboardingPhotoNumber(index + 1),
      ),
      subtitle: settled && faceAnchor == FaceAnchorPhotoStatus.verified
          ? const Align(
              alignment: AlignmentDirectional.centerStart,
              child: FaceAnchorBadge(),
            )
          : Text(
              draft.isUploading
                  ? l10n.photoUploadingPercent(percent)
                  : draft.error != null
                  ? l10n.photoUploadFailed
                  : draft.remote != null
                  ? FaceAnchorL10n.photoStatus(l10n, faceAnchor) ??
                        l10n.photoUploaded
                  : l10n.photoSelected,
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canVerify)
            TextButton(
              onPressed: enabled ? onVerify : null,
              child: Text(
                faceAnchor == FaceAnchorPhotoStatus.notVerified
                    ? l10n.faceAnchorRetry
                    : l10n.faceAnchorVerifyShort,
              ),
            ),
          if (draft.error != null)
            IconButton(
              tooltip: l10n.photoRetry,
              icon: const Icon(MevoraIcons.refresh),
              onPressed: enabled ? onRetry : null,
            ),
          IconButton(
            icon: const Icon(MevoraIcons.delete),
            onPressed: enabled ? onRemove : null,
          ),
        ],
      ),
    );
  }
}
