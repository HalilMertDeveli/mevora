import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/photo_policy.dart';
import 'package:mevora/features/settings/domain/validators/profile_edit_validator.dart';
import 'package:mevora/features/settings/presentation/settings_strings.dart';
import 'package:mevora/features/settings/presentation/widgets/photo_grid_editor.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';
import 'package:mevora/shared/widgets/turkish_province_picker.dart';

/// Editable profile fields. Birth date is locked after onboarding.
class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _firstNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _educationController = TextEditingController();
  final _interestsController = TextEditingController();
  UserProfile? _profile;
  String? _gender;
  String? _interestedIn;
  String? _relationshipGoal;
  String? _errorKey;
  var _saving = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _educationController.dispose();
    _interestsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final uid = AuthScope.of(context).user?.id;
    final settings = SettingsScope.maybeOf(context);
    if (uid == null || settings == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    return StreamBuilder<UserProfile?>(
      stream: settings.settingsHub.watchProfile(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? _profile;
        if (profile != null && _profile?.uid != profile.uid) {
          _hydrate(profile);
        }
        return Scaffold(
          appBar: AppBar(title: Text(l10n.editProfile)),
          body: profile == null
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.screenPadding),
                    children: [
                      PhotoGridEditor(
                        photos: profile.photos,
                        onAdd: () => unawaited(_addPhoto(profile)),
                        onDelete: (id) => unawaited(_deletePhoto(profile, id)),
                        onReorder: (oldIndex, newIndex) =>
                            unawaited(_reorder(profile, oldIndex, newIndex)),
                        onSetPrimary: (id) =>
                            unawaited(_setPrimary(profile, id)),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      MevoraTextField(
                        controller: _firstNameController,
                        label: l10n.onboardingFirstName,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MevoraTextField(
                        controller: _bioController,
                        label: l10n.bio,
                        maxLines: 4,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _optionField(
                        l10n.settingsGender,
                        _gender,
                        const ['woman', 'man', 'nonBinary'],
                        (value) => setState(() => _gender = value),
                        SettingsStrings.genderLabel,
                      ),
                      _optionField(
                        l10n.settingsInterestedIn,
                        _interestedIn,
                        const ['woman', 'man', 'everyone'],
                        (value) => setState(() => _interestedIn = value),
                        SettingsStrings.genderLabel,
                      ),
                      MevoraTextField(
                        controller: _cityController,
                        label: l10n.settingsCity,
                        readOnly: true,
                        suffixIcon: const Icon(Icons.arrow_drop_down),
                        onTap: _saving
                            ? null
                            : () => unawaited(_pickCity()),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MevoraTextField(
                        controller: _educationController,
                        label: l10n.settingsEducation,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      MevoraTextField(
                        controller: _interestsController,
                        label: l10n.interests,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _optionField(
                        l10n.settingsRelationshipGoal,
                        _relationshipGoal,
                        const ['longTerm', 'casual', 'figuringOut'],
                        (value) => setState(() => _relationshipGoal = value),
                        SettingsStrings.relationshipGoalLabel,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (profile.birthDate != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.onboardingBirthDate),
                          subtitle: Text(
                            '${profile.birthDate!.toLocal().toString().split(' ').first}\n${l10n.settingsBirthDateLocked}',
                          ),
                        ),
                      if (_errorKey != null) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          SettingsStrings.validation(l10n, _errorKey),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      MevoraButton(
                        label: l10n.settingsSaveProfile,
                        isLoading: _saving,
                        onPressed: _saving
                            ? null
                            : () => unawaited(_save(profile, settings)),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _hydrate(UserProfile profile) {
    _profile = profile;
    _firstNameController.text = profile.displayName;
    _bioController.text = profile.bio ?? '';
    _cityController.text = profile.city ?? '';
    _educationController.text = profile.education ?? '';
    _interestsController.text = profile.interests.join(', ');
    _gender = profile.gender;
    _interestedIn = profile.interestedIn;
    _relationshipGoal = profile.relationshipGoal;
  }

  Widget _optionField(
    String label,
    String? value,
    List<String> options,
    ValueChanged<String> onChanged,
    String Function(AppLocalizations, String?) labelFor,
  ) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: DropdownButtonFormField<String>(
        value: options.contains(value) ? value : null,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option,
              child: Text(labelFor(l10n, option)),
            ),
        ],
        onChanged: (next) {
          if (next != null) {
            onChanged(next);
          }
        },
      ),
    );
  }

  Future<void> _pickCity() async {
    final picked = await showTurkishProvincePicker(context);
    if (picked == null || !mounted) return;
    setState(() => _cityController.text = picked);
  }

  Future<void> _save(UserProfile profile, SettingsServices settings) async {
    final l10n = AppLocalizations.of(context);
    final interests = _interestsController.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    final next = profile.copyWith(
      displayName: _firstNameController.text.trim(),
      bio: _bioController.text.trim(),
      gender: _gender,
      interestedIn: _interestedIn,
      city: _cityController.text.trim(),
      education: _educationController.text.trim(),
      interests: interests,
      relationshipGoal: _relationshipGoal,
    );
    final validation = ProfileEditValidator.validateProfile(next);
    if (validation != null) {
      setState(() => _errorKey = validation);
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    await settings.settingsHub.saveProfile(next);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsProfileSaved)),
      );
      context.pop();
    }
  }

  Future<void> _addPhoto(UserProfile profile) async {
    final settings = SettingsScope.of(context);
    final permission = PermissionScope.of(context).controller;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(l10n.addPhotoCamera),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: Text(l10n.addPhotoGallery),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
            ],
          ),
        );
      },
    );
    if (picked == null || !mounted) {
      return;
    }
    final type = picked == 'camera'
        ? PermissionType.camera
        : PermissionType.photos;
    await PermissionPromptPage.show(
      context,
      type: type,
      controller: permission,
    );
    final photo = picked == 'camera'
        ? await settings.photoPicker.pickFromCamera()
        : await settings.photoPicker.pickFromGallery();
    if (!mounted) {
      return;
    }
    if (photo.isError) {
      setState(() => _errorKey = photo.failureOrNull?.message);
      return;
    }
    final pickedPhoto = photo.valueOrNull!;
    final imageId = DateTime.now().millisecondsSinceEpoch.toString();
    final result = await settings.photoManager.addPhoto(
      profile: profile,
      imageId: imageId,
      bytes: pickedPhoto.bytes,
      contentType: pickedPhoto.contentType,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) {},
      err: (failure) => setState(() => _errorKey = failure.message),
    );
  }

  Future<void> _deletePhoto(UserProfile profile, String photoId) async {
    final settings = SettingsScope.of(context);
    final block = PhotoPolicy.deleteBlockReason(profile.photos, photoId);
    if (block != null) {
      setState(() => _errorKey = block);
      return;
    }
    final result = await settings.photoManager.deletePhoto(
      profile: profile,
      photoId: photoId,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (_) {},
      err: (failure) => setState(() => _errorKey = failure.message),
    );
  }

  Future<void> _reorder(
    UserProfile profile,
    int oldIndex,
    int newIndex,
  ) async {
    final settings = SettingsScope.of(context);
    await settings.photoManager.reorderPhotos(
      profile: profile,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _setPrimary(UserProfile profile, String photoId) async {
    final settings = SettingsScope.of(context);
    await settings.photoManager.setPrimaryPhoto(
      profile: profile,
      photoId: photoId,
    );
  }
}
