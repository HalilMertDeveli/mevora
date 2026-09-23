import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_photo_grid.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_step_scaffold.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/features/music/presentation/widgets/onboarding_music_step.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_height_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_language_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_education_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_gender_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_interest_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_relationship_goal_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_motion_size.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/turkish_province_picker.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final OnboardingController _controller;
  final _firstNameController = TextEditingController();
  final _cityController = TextEditingController();
  final _bioController = TextEditingController();
  final _birthDateLabelController = TextEditingController();
  DateTime? _birthDate;
  bool _listenerAttached = false;
  String? _initializedUid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listenerAttached) {
      _controller = OnboardingScope.of(context).controller;
      _controller.addListener(_syncFields);
      _listenerAttached = true;
    }
    final user = AuthScope.of(context).user;
    final uid = user?.id;
    if (uid != null && uid != _initializedUid) {
      _initializedUid = uid;
      unawaited(_controller.initialize(user!));
    }
  }

  @override
  void initState() {
    super.initState();
  }

  void _syncFields() {
    if (!mounted) {
      return;
    }
    final profile = _controller.profile;
    if (profile == null) {
      return;
    }
    if (_firstNameController.text != profile.displayName) {
      _firstNameController.text = profile.displayName;
    }
    if (_cityController.text != (profile.city ?? '')) {
      _cityController.text = profile.city ?? '';
    }
    if (_bioController.text != (profile.bio ?? '')) {
      _bioController.text = profile.bio ?? '';
    }
    _birthDate = profile.birthDate;
    final birthLabel = _birthDate == null
        ? ''
        : MaterialLocalizations.of(context).formatMediumDate(_birthDate!);
    if (_birthDateLabelController.text != birthLabel) {
      _birthDateLabelController.text = birthLabel;
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) {
      _controller.removeListener(_syncFields);
    }
    _firstNameController.dispose();
    _cityController.dispose();
    _bioController.dispose();
    _birthDateLabelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading || _controller.profile == null) {
          return Scaffold(
            body: SafeArea(
              child: MevoraLoading.page(
                message: AppLocalizations.of(context).onboardingTitle,
              ),
            ),
          );
        }
        return Scaffold(
          resizeToAvoidBottomInset: true,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              child: AnimatedSwitcher(
                duration: AppDurations.short,
                child: KeyedSubtree(
                  key: ValueKey(_controller.step),
                  child: _buildStep(context),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (_controller.step) {
      OnboardingStep.basicInfo => _basicInfoStep(l10n),
      OnboardingStep.interests => _interestsStep(l10n),
      OnboardingStep.education => _educationStep(l10n),
      OnboardingStep.relationshipGoal => _relationshipStep(l10n),
      OnboardingStep.lifestyle => _lifestyleStep(l10n),
      OnboardingStep.bio => _bioStep(l10n),
      OnboardingStep.photos => _photosStep(l10n),
      OnboardingStep.music => _musicStep(l10n),
      OnboardingStep.complete => _completeStep(l10n),
    };
  }

  /// Optional Spotify stage. Rendered only when a music repository is in
  /// scope; without one the step skips itself rather than dead-ending.
  Widget _musicStep(AppLocalizations l10n) {
    final repository = MusicScope.maybeOf(context);
    if (repository == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_continue());
      });
      return const SizedBox.shrink();
    }
    return OnboardingStepScaffold(
      step: OnboardingStep.music,
      title: l10n.onboardingMusicTitle,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.canGoBack ? _controller.goBack : null,
      onContinue: () => unawaited(_continue()),
      showContinue: false,
      child: OnboardingMusicStep(
        repository: repository,
        onSkip: () => unawaited(_continue()),
        onFinished: () => unawaited(_continue()),
      ),
    );
  }

  Widget _basicInfoStep(AppLocalizations l10n) {
    final profile = _controller.profile!;
    return OnboardingStepScaffold(
      step: OnboardingStep.basicInfo,
      title: l10n.onboardingTitle,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.canGoBack ? _controller.goBack : null,
      onContinue: () => unawaited(_continue()),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          MevoraTextField(
            controller: _firstNameController,
            label: l10n.onboardingFirstName,
            textCapitalization: TextCapitalization.words,
            onChanged: (value) => _controller.updateDraft(
              (current) => current.copyWith(displayName: value),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            readOnly: true,
            label: l10n.onboardingBirthDate,
            controller: _birthDateLabelController,
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _controller.isSaving ? null : _pickBirthDate,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingGender,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ProfileGenderPicker(
                value: profile.gender,
                onChanged: (value) => _controller.updateDraft(
                  (current) => current.copyWith(gender: value),
                ),
                enabled: !_controller.isSaving,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingInterestedIn,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ProfileInterestedInPicker(
            value: profile.interestedIn,
            onChanged: (value) => _controller.updateDraft(
              (current) => current.copyWith(interestedIn: value),
            ),
            enabled: !_controller.isSaving,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingHeight,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ProfileHeightPicker(
            valueCm: profile.heightCm,
            onChanged: (value) => _controller.updateDraft(
              (current) => current.copyWith(heightCm: value),
            ),
            enabled: !_controller.isSaving,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingLanguages,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          ProfileLanguagePicker(
            selected: profile.languages.toSet(),
            onChanged: (next) => _controller.updateDraft(
              (current) => current.copyWith(languages: next.toList()),
            ),
            enabled: !_controller.isSaving,
            showHint: true,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            controller: _cityController,
            label: l10n.onboardingCity,
            readOnly: true,
            suffixIcon: const Icon(Icons.arrow_drop_down),
            onTap: _controller.isSaving ? null : () => unawaited(_pickCity()),
          ),
        ],
      ),
    );
  }

  Widget _interestsStep(AppLocalizations l10n) {
    final selected = _controller.profile!.interests.toSet();
    return OnboardingStepScaffold(
      step: OnboardingStep.interests,
      title: l10n.onboardingInterests,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ProfileInterestPicker(
        selected: selected,
        onChanged: (next) => _controller.updateDraft(
          (current) => current.copyWith(interests: next.toList()),
        ),
        enabled: !_controller.isSaving,
      ),
    );
  }

  Widget _educationStep(AppLocalizations l10n) {
    final education = _controller.profile!.education;
    return OnboardingStepScaffold(
      step: OnboardingStep.education,
      title: l10n.onboardingEducation,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ProfileEducationPicker(
        value: education,
        onChanged: (next) => _controller.updateDraft(
          (current) => current.copyWith(education: next),
        ),
        enabled: !_controller.isSaving,
      ),
    );
  }

  Widget _relationshipStep(AppLocalizations l10n) {
    final goal = _controller.profile!.relationshipGoal;
    return OnboardingStepScaffold(
      step: OnboardingStep.relationshipGoal,
      title: l10n.onboardingRelationshipGoal,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ProfileRelationshipGoalPicker(
        value: goal,
        onChanged: (next) => _controller.updateDraft(
          (current) => current.copyWith(relationshipGoal: next),
        ),
        enabled: !_controller.isSaving,
      ),
    );
  }

  Widget _lifestyleStep(AppLocalizations l10n) {
    final lifestyle = _controller.profile!.lifestyleProfile;
    return OnboardingStepScaffold(
      step: OnboardingStep.lifestyle,
      title: l10n.onboardingLifestyle,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ProfileLifestylePicker(
        profile: lifestyle,
        onChanged: (next) => _controller.updateDraft(
          (current) => current.copyWith(lifestyleProfile: next),
        ),
        enabled: !_controller.isSaving,
      ),
    );
  }

  Widget _bioStep(AppLocalizations l10n) {
    return OnboardingStepScaffold(
      step: OnboardingStep.bio,
      title: l10n.onboardingBio,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ListView(
        children: [
          MevoraTextField(
            controller: _bioController,
            label: l10n.onboardingBio,
            hint: l10n.onboardingBioHint,
            maxLines: 6,
            minLines: 4,
            maxLength: 500,
            onChanged: (value) => _controller.updateDraft(
              (current) => current.copyWith(bio: value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photosStep(AppLocalizations l10n) {
    return OnboardingStepScaffold(
      step: OnboardingStep.photos,
      title: l10n.onboardingPhotos,
      isSaving: _controller.isSaving,
      canContinue: _controller.canContinuePhotos,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      child: ListView(
        children: [
          OnboardingPhotoGrid(
            drafts: _controller.photoDrafts,
            enabled: !_controller.isSaving,
            onAddCamera: () =>
                unawaited(_controller.pickPhoto(fromCamera: true)),
            onAddGallery: () => unawaited(_controller.pickGalleryPhotos()),
            onRetry: (id) => unawaited(_controller.retryPhotoUpload(id)),
            onRemove: _controller.removePhoto,
            onReorder: _controller.reorderPhotos,
          ),
        ],
      ),
    );
  }

  Widget _completeStep(AppLocalizations l10n) {
    return OnboardingStepScaffold(
      step: OnboardingStep.complete,
      title: l10n.onboardingCompleteTitle,
      continueLabel: l10n.onboardingStartDiscovering,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_finish()),
      child: ListView(
        children: [
          Center(
            child: Builder(
              builder: (context) {
                final size = MevoraMotionSize.accent(context);
                return MevoraRiveAnimation(
                  asset: MevoraRiveAssets.onboardingComplete,
                  width: size,
                  height: size,
                  fallback: Icon(
                    Icons.auto_awesome_outlined,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.onboardingCompleteMessage,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }

  Future<void> _pickCity() async {
    final picked = await showTurkishProvincePicker(context);
    if (!mounted || picked == null) {
      return;
    }
    _cityController.text = picked;
    _controller.updateDraft((current) => current.copyWith(city: picked));
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 25),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (!mounted || picked == null) {
      return;
    }
    setState(() => _birthDate = picked);
    _birthDateLabelController.text =
        MaterialLocalizations.of(context).formatMediumDate(picked);
    _controller.updateDraft((current) => current.copyWith(birthDate: picked));
  }

  Future<void> _continue() async {
    if (_controller.step == OnboardingStep.photos) {
      await _controller.continueStep();
      return;
    }
    await _controller.continueStep();
  }

  Future<void> _finish() async {
    final result = await _controller.complete();
    if (!mounted) {
      return;
    }
    if (result.isError) {
      return;
    }
    AuthScope.of(context).applyOnboardingComplete();
  }
}
