import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/permission_scope.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/services/permissions/permission_type.dart';
import 'package:mevora/features/permissions/presentation/pages/permission_prompt_page.dart';
import 'package:mevora/features/profile/domain/entities/profile_lifestyle.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/profile/domain/services/profile_completion_calculator.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_completion_banner.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_extended_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_height_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_hobby_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_language_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_education_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_gender_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_interest_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_relationship_goal_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_section_header.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_question_answers_section.dart';
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

  final _occupationController = TextEditingController();
  UserProfile? _baseline;
  String? _gender;
  String? _interestedIn;
  String? _relationshipGoal;
  String? _education;
  int? _heightCm;
  Set<String> _interests = {};
  Set<String> _languages = {};
  Set<String> _hobbies = {};
  ProfileLifestyle _lifestyle = const ProfileLifestyle();
  String? _errorKey;
  var _saving = false;
  var _hydrated = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  bool get _hasUnsavedChanges {
    final baseline = _baseline;
    if (baseline == null || !_hydrated) {
      return false;
    }
    return !_profilesEqual(baseline, _buildDraft(baseline));
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
        final profile = snapshot.data;
        if (profile != null && (!_hydrated || _baseline?.uid != profile.uid)) {
          _hydrate(profile);
        }
        return PopScope(
          canPop: !_hasUnsavedChanges,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) {
              return;
            }
            final discard = await _confirmDiscard(l10n);
            if (discard && context.mounted) {
              context.pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(title: Text(l10n.editProfile)),
            body: profile == null
                ? const Center(child: CircularProgressIndicator())
                : SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.screenPadding),
                      children: [
                        ProfileCompletionBanner(
                          result: ProfileCompletionCalculator.calculate(profile),
                        ),
                        ProfileSectionHeader(title: l10n.profileEditSectionPhotos),
                        PhotoGridEditor(
                          photos: profile.photos,
                          onAdd: () => unawaited(_addPhoto(profile, settings)),
                          onDelete: (id) =>
                              unawaited(_deletePhoto(profile, settings, id)),
                          onReorder: (oldIndex, newIndex) => unawaited(
                            _reorder(profile, settings, oldIndex, newIndex),
                          ),
                          onSetPrimary: (id) =>
                              unawaited(_setPrimary(profile, settings, id)),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionBasic,
                        ),
                        MevoraTextField(
                          controller: _firstNameController,
                          label: l10n.onboardingFirstName,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.onboardingGender,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileGenderPicker(
                          value: _gender,
                          onChanged: (value) =>
                              setState(() => _gender = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.onboardingInterestedIn,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileInterestedInPicker(
                          value: _interestedIn,
                          onChanged: (value) =>
                              setState(() => _interestedIn = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.profileHeightLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ProfileHeightPicker(
                          valueCm: _heightCm,
                          onChanged: (value) =>
                              setState(() => _heightCm = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MevoraTextField(
                          controller: _cityController,
                          label: l10n.settingsCity,
                          readOnly: true,
                          suffixIcon: const Icon(Icons.arrow_drop_down),
                          onTap: _saving ? null : () => unawaited(_pickCity()),
                        ),
                        if (profile.birthDate != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(l10n.onboardingBirthDate),
                            subtitle: Text(
                              '${profile.birthDate!.toLocal().toString().split(' ').first}\n${l10n.settingsBirthDateLocked}',
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(title: l10n.profileEditSectionAbout),
                        MevoraTextField(
                          controller: _bioController,
                          label: l10n.bio,
                          maxLines: 4,
                          maxLength: ProfileEditValidator.maxBioLength,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          l10n.onboardingEducation,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        ProfileEducationPicker(
                          value: _education,
                          onChanged: (value) =>
                              setState(() => _education = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        MevoraTextField(
                          controller: _occupationController,
                          label: l10n.profileOccupationLabel,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionLanguages,
                          subtitle: l10n.profileLanguagesHint,
                        ),
                        ProfileLanguagePicker(
                          selected: _languages,
                          onChanged: (value) =>
                              setState(() => _languages = value),
                          enabled: !_saving,
                          showHint: false,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionInterests,
                          subtitle: l10n.onboardingInterestsHint,
                        ),
                        ProfileInterestPicker(
                          selected: _interests,
                          onChanged: (value) =>
                              setState(() => _interests = value),
                          enabled: !_saving,
                          showHint: false,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionLifestyle,
                        ),
                        ProfileLifestylePicker(
                          profile: _lifestyle,
                          onChanged: (value) =>
                              setState(() => _lifestyle = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionExtended,
                        ),
                        ProfileExtendedLifestylePicker(
                          profile: _lifestyle,
                          onChanged: (value) =>
                              setState(() => _lifestyle = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionHobbies,
                          subtitle: l10n.profileHobbiesHint,
                        ),
                        ProfileHobbyPicker(
                          selected: _hobbies,
                          onChanged: (value) =>
                              setState(() => _hobbies = value),
                          enabled: !_saving,
                          showHint: false,
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionRelationship,
                        ),
                        ProfileRelationshipGoalPicker(
                          value: _relationshipGoal,
                          onChanged: (value) =>
                              setState(() => _relationshipGoal = value),
                          enabled: !_saving,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l10n.profileEditDiscoveryPrefs),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () =>
                              context.push(AppRoutes.discoveryPreferences),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ProfileSectionHeader(
                          title: l10n.profileEditSectionAnswers,
                          subtitle: l10n.profileEditAnswersSubtitle,
                        ),
                        ProfileQuestionAnswersSection(
                          uid: uid,
                          isOwner: true,
                          showEditAction: true,
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
                          label: l10n.saveChanges,
                          isLoading: _saving,
                          onPressed: _saving || !_hasUnsavedChanges
                              ? null
                              : () => unawaited(_save(profile, settings, uid)),
                        ),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  void _hydrate(UserProfile profile) {
    _baseline = profile;
    _firstNameController.text = profile.displayName;
    _bioController.text = profile.bio ?? '';
    _cityController.text = profile.city ?? '';
    _gender = profile.gender;
    _interestedIn = profile.interestedIn;
    _relationshipGoal = profile.relationshipGoal;
    _education = profile.education;
    _heightCm = profile.heightCm;
    _occupationController.text = profile.occupation ?? '';
    _interests = profile.interests.toSet();
    _languages = profile.languages.toSet();
    _hobbies = profile.hobbies.toSet();
    _lifestyle = profile.lifestyleProfile;
    _hydrated = true;
  }

  UserProfile _buildDraft(UserProfile profile) {
    return profile.copyWith(
      displayName: _firstNameController.text.trim(),
      bio: _bioController.text.trim(),
      gender: _gender,
      interestedIn: _interestedIn,
      city: _cityController.text.trim(),
      education: _education,
      occupation: _occupationController.text.trim().isEmpty
          ? null
          : _occupationController.text.trim(),
      heightCm: _heightCm,
      interests: _interests.toList(),
      languages: _languages.toList(),
      hobbies: _hobbies.toList(),
      relationshipGoal: _relationshipGoal,
      lifestyleProfile: _lifestyle,
      lifestyle: _lifestyle.toTags(),
    );
  }

  bool _profilesEqual(UserProfile a, UserProfile b) {
    return a.displayName == b.displayName &&
        (a.bio ?? '') == (b.bio ?? '') &&
        a.gender == b.gender &&
        a.interestedIn == b.interestedIn &&
        (a.city ?? '') == (b.city ?? '') &&
        a.education == b.education &&
        (a.occupation ?? '') == (b.occupation ?? '') &&
        a.heightCm == b.heightCm &&
        a.relationshipGoal == b.relationshipGoal &&
        _setEquals(a.interests.toSet(), b.interests.toSet()) &&
        _setEquals(a.languages.toSet(), b.languages.toSet()) &&
        _setEquals(a.hobbies.toSet(), b.hobbies.toSet()) &&
        a.lifestyleProfile.smoking == b.lifestyleProfile.smoking &&
        a.lifestyleProfile.drinking == b.lifestyleProfile.drinking &&
        a.lifestyleProfile.exercise == b.lifestyleProfile.exercise &&
        a.lifestyleProfile.pets == b.lifestyleProfile.pets &&
        a.lifestyleProfile.partnerSmokingPref ==
            b.lifestyleProfile.partnerSmokingPref &&
        a.lifestyleProfile.partnerDrinkingPref ==
            b.lifestyleProfile.partnerDrinkingPref &&
        a.lifestyleProfile.childrenPreference ==
            b.lifestyleProfile.childrenPreference &&
        a.lifestyleProfile.partnerChildrenPref ==
            b.lifestyleProfile.partnerChildrenPref &&
        a.lifestyleProfile.socialRhythm == b.lifestyleProfile.socialRhythm &&
        a.lifestyleProfile.socialLevel == b.lifestyleProfile.socialLevel &&
        _setEquals(
          a.lifestyleProfile.weekendPreferences.toSet(),
          b.lifestyleProfile.weekendPreferences.toSet(),
        ) &&
        a.lifestyleProfile.cohabitationPreference ==
            b.lifestyleProfile.cohabitationPreference;
  }

  bool _setEquals<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) {
      return false;
    }
    return a.containsAll(b);
  }

  Future<bool> _confirmDiscard(AppLocalizations l10n) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.discardChangesTitle),
        content: Text(l10n.discardChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.keepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _pickCity() async {
    final picked = await showTurkishProvincePicker(context);
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _cityController.text = picked);
  }

  Future<void> _save(
    UserProfile profile,
    SettingsServices settings,
    String uid,
  ) async {
    final l10n = AppLocalizations.of(context);
    final next = _buildDraft(profile);
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
    settings.profileUpdates.notifyProfileUpdated(uid);
    if (mounted) {
      setState(() {
        _saving = false;
        _baseline = next;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsProfileSaved)),
      );
      context.pop();
    }
  }

  Future<void> _addPhoto(UserProfile profile, SettingsServices settings) async {
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

  Future<void> _deletePhoto(
    UserProfile profile,
    SettingsServices settings,
    String photoId,
  ) async {
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
    SettingsServices settings,
    int oldIndex,
    int newIndex,
  ) async {
    await settings.photoManager.reorderPhotos(
      profile: profile,
      oldIndex: oldIndex,
      newIndex: newIndex,
    );
  }

  Future<void> _setPrimary(
    UserProfile profile,
    SettingsServices settings,
    String photoId,
  ) async {
    await settings.photoManager.setPrimaryPhoto(
      profile: profile,
      photoId: photoId,
    );
  }
}

