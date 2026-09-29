import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/images/mevora_network_images.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_icon_button.dart';
import 'package:mevora/shared/widgets/mevora_pill.dart';

/// The owner's photo list on the edit page: drag the handle to reorder, the
/// menu to make a photo the main one or remove it. The section heading is
/// the page's; this widget only draws the rows.
class PhotoGridEditor extends StatelessWidget {
  const PhotoGridEditor({
    super.key,
    required this.photos,
    required this.onAdd,
    required this.onDelete,
    required this.onReorder,
    required this.onSetPrimary,
  });

  final List<ProfilePhoto> photos;
  final VoidCallback onAdd;
  final ValueChanged<String> onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<String> onSetPrimary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sorted = [...photos]..sort((a, b) => a.order.compareTo(b.order));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // The handle starts a drag at once; the list's own reorder
          // semantics actions still serve screen readers.
          buildDefaultDragHandles: false,
          itemCount: sorted.length,
          onReorder: (oldIndex, newIndex) {
            final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
            onReorder(oldIndex, adjusted);
          },
          itemBuilder: (context, index) {
            final photo = sorted[index];
            return Padding(
              key: ValueKey(photo.id),
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _PhotoRow(
                photo: photo,
                index: index,
                label: photo.isPrimary
                    ? l10n.onboardingPrimaryPhoto
                    : l10n.onboardingPhotoNumber(index + 1),
                onMenu: () => unawaited(_openMenu(context, photo)),
              ),
            );
          },
        ),
        if (PhotoPolicy.canAdd(sorted.length))
          _AddPhotoRow(label: l10n.settingsAddPhoto, onTap: onAdd),
      ],
    );
  }

  Future<void> _openMenu(BuildContext context, ProfilePhoto photo) async {
    final l10n = AppLocalizations.of(context);
    final choice = await MevoraBottomSheet.showActions<String>(
      context,
      actions: [
        if (!photo.isPrimary)
          MevoraSheetAction(
            value: 'primary',
            label: l10n.settingsSetPrimaryPhoto,
            icon: MevoraIcons.star,
          ),
        MevoraSheetAction(
          value: 'delete',
          label: l10n.settingsDeletePhoto,
          icon: MevoraIcons.delete,
          destructive: true,
        ),
      ],
    );
    switch (choice) {
      case 'primary':
        onSetPrimary(photo.id);
      case 'delete':
        onDelete(photo.id);
    }
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.photo,
    required this.index,
    required this.label,
    required this.onMenu,
  });

  final ProfilePhoto photo;
  final int index;
  final String label;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final provider = MevoraNetworkImages.provider(photo.downloadUrl);
    final placeholder = ColoredBox(
      color: p.surfaceMuted,
      child: Icon(MevoraIcons.photo, color: p.textTertiary),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: p.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 48,
                  child: Icon(MevoraIcons.dragHandle, color: p.textTertiary),
                ),
              ),
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                width: 54,
                height: 72,
                child: provider == null
                    ? placeholder
                    : Image(
                        image: provider,
                        fit: BoxFit.cover,
                        frameBuilder: (context, child, frame, sync) =>
                            sync || frame != null ? child : placeholder,
                        errorBuilder: (_, _, _) => placeholder,
                      ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: photo.isPrimary
                    ? MevoraPill(
                        label: label,
                        icon: MevoraIcons.star,
                        tone: MevoraTone.accent,
                      )
                    : Text(label, style: theme.textTheme.bodyLarge),
              ),
            ),
            MevoraIconButton(
              icon: MevoraIcons.more,
              tooltip: l10n.more,
              onPressed: onMenu,
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoRow extends StatelessWidget {
  const _AddPhotoRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final radius = BorderRadius.circular(AppRadii.lg);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: p.borderStrong),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(MevoraIcons.addPhoto, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
