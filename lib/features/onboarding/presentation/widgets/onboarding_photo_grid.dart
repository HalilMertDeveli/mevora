import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_config.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/animations/mevora_status_motion.dart';
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
  });

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
        Text(l10n.onboardingPhotosHint),
        const SizedBox(height: AppSpacing.md),
        if (drafts.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: MevoraStatusMotion(
              kind: MevoraMotionKind.empty,
              riveAsset: MevoraRiveAssets.photoUpload,
              label: l10n.photoEmptyHint,
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
              onRetry: () => onRetry(draft.id),
              onRemove: () => onRemove(draft.id),
            );
          },
        ),
        if (drafts.length < OnboardingConfig.minPhotos) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.photoMinRequired,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (canAdd) ...[
          MevoraButton(
            label: l10n.addPhotoCamera,
            icon: Icons.photo_camera_outlined,
            onPressed: enabled ? onAddCamera : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          MevoraButton(
            label: l10n.addPhotoGallery,
            icon: Icons.photo_library_outlined,
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
    required this.onRetry,
    required this.onRemove,
  });

  final OnboardingPhotoDraft draft;
  final int index;
  final bool enabled;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final percent = (draft.progress * 100).round();
    ImageProvider? image;
    final bytes = draft.localBytes;
    if (bytes != null && bytes.isNotEmpty) {
      image = MemoryImage(Uint8List.fromList(bytes));
    } else if (draft.remote?.downloadUrl != null) {
      image = NetworkImage(draft.remote!.downloadUrl!);
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
                  child: const Icon(Icons.person_outline),
                ),
              if (draft.isUploading)
                ColoredBox(
                  color: Colors.black45,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      MevoraRiveAnimation(
                        asset: MevoraRiveAssets.photoUpload,
                        width: 22,
                        height: 22,
                        fallback: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      Text(
                        '$percent%',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              if (draft.error != null && !draft.isUploading)
                ColoredBox(
                  color: Colors.black45,
                  child: MevoraRiveAnimation(
                    asset: MevoraRiveAssets.error,
                    width: 20,
                    height: 20,
                    fallback: Icon(
                      Icons.error_outline,
                      size: 18,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              if (draft.remote != null && !draft.isUploading)
                const Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check_circle, size: 16, color: Colors.white),
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
      subtitle: Text(
        draft.isUploading
            ? l10n.photoUploadingPercent(percent)
            : draft.error != null
            ? l10n.photoUploadFailed
            : draft.remote != null
            ? l10n.photoUploaded
            : l10n.photoSelected,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (draft.error != null)
            IconButton(
              tooltip: l10n.photoRetry,
              icon: const Icon(Icons.refresh),
              onPressed: enabled ? onRetry : null,
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: enabled ? onRemove : null,
          ),
        ],
      ),
    );
  }
}
