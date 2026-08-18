import 'package:flutter/material.dart';
import 'package:mevora/core/services/permissions/permission_status.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/l10n/app_localizations.dart';

abstract final class PermissionCopy {
  static String title(AppLocalizations l10n, PermissionType type) {
    return switch (type) {
      PermissionType.camera => l10n.permissionCameraTitle,
      PermissionType.microphone => l10n.permissionMicrophoneTitle,
      PermissionType.photos => l10n.permissionPhotosTitle,
      PermissionType.notifications => l10n.permissionNotificationsTitle,
      PermissionType.location => l10n.permissionLocationTitle,
    };
  }

  static String description(AppLocalizations l10n, PermissionType type) {
    return switch (type) {
      PermissionType.camera => l10n.permissionCameraDescription,
      PermissionType.microphone => l10n.permissionMicrophoneDescription,
      PermissionType.photos => l10n.permissionPhotosDescription,
      PermissionType.notifications => l10n.permissionNotificationsDescription,
      PermissionType.location => l10n.permissionLocationDescription,
    };
  }

  static String statusLabel(AppLocalizations l10n, PermissionStatus status) {
    return switch (status) {
      PermissionStatus.granted => l10n.permissionStatusGranted,
      PermissionStatus.denied => l10n.permissionStatusDenied,
      PermissionStatus.restricted => l10n.permissionStatusRestricted,
      PermissionStatus.limited => l10n.permissionStatusLimited,
      PermissionStatus.permanentlyDenied =>
        l10n.permissionStatusPermanentlyDenied,
      PermissionStatus.unknown => l10n.permissionStatusUnknown,
    };
  }

  static IconData icon(PermissionType type) {
    return switch (type) {
      PermissionType.camera => Icons.photo_camera_outlined,
      PermissionType.microphone => Icons.mic_none_outlined,
      PermissionType.photos => Icons.photo_library_outlined,
      PermissionType.notifications => Icons.notifications_outlined,
      PermissionType.location => Icons.place_outlined,
    };
  }
}
