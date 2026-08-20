import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/l10n/app_localizations.dart';

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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.photos, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: sorted.length + (PhotoPolicy.canAdd(sorted.length) ? 1 : 0),
          onReorder: (oldIndex, newIndex) {
            if (oldIndex >= sorted.length || newIndex > sorted.length) {
              return;
            }
            final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
            onReorder(oldIndex, adjusted);
          },
          itemBuilder: (context, index) {
            if (index == sorted.length) {
              return ListTile(
                key: const ValueKey('add_photo'),
                leading: const Icon(Icons.add_a_photo_outlined),
                title: Text(l10n.settingsAddPhoto),
                onTap: onAdd,
              );
            }
            final photo = sorted[index];
            return ListTile(
              key: ValueKey(photo.id),
              leading: CircleAvatar(
                backgroundImage: photo.downloadUrl == null
                    ? null
                    : NetworkImage(photo.downloadUrl!),
                child: photo.downloadUrl == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(
                photo.isPrimary
                    ? '${l10n.settingsSetPrimaryPhoto} ✓'
                    : l10n.photos,
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'primary') {
                    onSetPrimary(photo.id);
                  } else if (value == 'delete') {
                    onDelete(photo.id);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'primary',
                    child: Text(l10n.settingsSetPrimaryPhoto),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.settingsDeletePhoto),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
