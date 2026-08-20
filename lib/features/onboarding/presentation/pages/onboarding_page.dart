import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_enums.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/onboarding/domain/entities/interest_option.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_photo_grid.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_step_scaffold.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/animations/mevora_rive_animation.dart';
import 'package:mevora/shared/animations/mevora_rive_assets.dart';
import 'package:mevora/shared/widgets/turkish_province_picker.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';
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
  DateTime? _birthDate;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) {
      return;
    }
    _initialized = true;
    _controller = OnboardingScope.of(context).controller;
    _controller.addListener(_syncFields);
    final user = AuthScope.of(context).user;
    if (user != null) {
      unawaited(_controller.initialize(user));
    }
  }

  @override
  void initState() {
    super.initState();
  }

  void _syncFields() {
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
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFields);
    _firstNameController.dispose();
    _cityController.dispose();
    _bioController.dispose();
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
      OnboardingStep.complete => _completeStep(l10n),
    };
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
            controller: TextEditingController(
              text: _birthDate == null
                  ? ''
                  : MaterialLocalizations.of(context).formatMediumDate(
                      _birthDate!,
                    ),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today_outlined),
              onPressed: _controller.isSaving ? null : _pickBirthDate,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.onboardingGender, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in OnboardingGender.values)
                MevoraChip(
                  label: _genderLabel(l10n, value),
                  selected: profile.gender == value,
                  onSelected: (_) => _controller.updateDraft(
                    (current) => current.copyWith(gender: value),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.onboardingInterestedIn,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in OnboardingInterestedIn.values)
                MevoraChip(
                  label: _interestedLabel(l10n, value),
                  selected: profile.interestedIn == value,
                  onSelected: (_) => _controller.updateDraft(
                    (current) => current.copyWith(interestedIn: value),
                  ),
                ),
            ],
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
      child: ListView(
        children: [
          Text(l10n.onboardingInterestsHint),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final option in InterestCatalog.options)
                MevoraChip(
                  label: _interestLabel(l10n, option.id),
                  avatar: Icon(option.icon, size: 18),
                  selected: selected.contains(option.id),
                  onSelected: (value) {
                    _controller.updateDraft((current) {
                      final next = {...current.interests};
                      if (value) {
                        next.add(option.id);
                      } else {
                        next.remove(option.id);
                      }
                      return current.copyWith(interests: next.toList());
                    });
                  },
                ),
            ],
          ),
        ],
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
      child: ListView(
        children: [
          for (final value in OnboardingEducation.values)
            RadioListTile<String>(
              value: value,
              groupValue: education,
              title: Text(_educationLabel(l10n, value)),
              onChanged: _controller.isSaving
                  ? null
                  : (next) => _controller.updateDraft(
                      (current) => current.copyWith(education: next),
                    ),
            ),
        ],
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
      child: ListView(
        children: [
          for (final value in OnboardingRelationshipGoal.values)
            RadioListTile<String>(
              value: value,
              groupValue: goal,
              title: Text(_relationshipLabel(l10n, value)),
              onChanged: _controller.isSaving
                  ? null
                  : (next) => _controller.updateDraft(
                      (current) => current.copyWith(relationshipGoal: next),
                    ),
            ),
        ],
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
      child: ListView(
        children: [
          _lifestyleGroup(
            l10n.onboardingSmoking,
            lifestyle.smoking,
            OnboardingLifestyleOption.habitValues,
            (value) => _controller.updateDraft(
              (current) => current.copyWith(
                lifestyleProfile: current.lifestyleProfile.copyWith(
                  smoking: value,
                ),
              ),
            ),
            l10n,
          ),
          _lifestyleGroup(
            l10n.onboardingDrinking,
            lifestyle.drinking,
            OnboardingLifestyleOption.habitValues,
            (value) => _controller.updateDraft(
              (current) => current.copyWith(
                lifestyleProfile: current.lifestyleProfile.copyWith(
                  drinking: value,
                ),
              ),
            ),
            l10n,
          ),
          _lifestyleGroup(
            l10n.onboardingExercise,
            lifestyle.exercise,
            OnboardingLifestyleOption.habitValues,
            (value) => _controller.updateDraft(
              (current) => current.copyWith(
                lifestyleProfile: current.lifestyleProfile.copyWith(
                  exercise: value,
                ),
              ),
            ),
            l10n,
          ),
          _lifestyleGroup(
            l10n.onboardingPets,
            lifestyle.pets,
            OnboardingLifestyleOption.petValues,
            (value) => _controller.updateDraft(
              (current) => current.copyWith(
                lifestyleProfile: current.lifestyleProfile.copyWith(pets: value),
              ),
            ),
            l10n,
          ),
        ],
      ),
    );
  }

  Widget _lifestyleGroup(
    String title,
    String? selected,
    List<String> values,
    ValueChanged<String> onChanged,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final value in values)
                MevoraChip(
                  label: _lifestyleLabel(l10n, value),
                  selected: selected == value,
                  onSelected: (_) => onChanged(value),
                ),
            ],
          ),
        ],
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
            onAddGallery: () =>
                unawaited(_controller.pickPhoto(fromCamera: false)),
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
            child: MevoraRiveAnimation(
              asset: MevoraRiveAssets.onboardingComplete,
              width: 120,
              height: 120,
              fallback: Icon(
                Icons.auto_awesome_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
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
    if (picked == null) return;
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
    if (picked == null) {
      return;
    }
    setState(() => _birthDate = picked);
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
    if (!mounted || result.isError) {
      return;
    }
    AuthScope.of(context).applyOnboardingComplete();
  }

  String _genderLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      OnboardingGender.man => l10n.onboardingGenderMan,
      OnboardingGender.woman => l10n.onboardingGenderWoman,
      OnboardingGender.nonBinary => l10n.onboardingGenderNonBinary,
      _ => value,
    };
  }

  String _interestedLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      OnboardingInterestedIn.men => l10n.onboardingInterestedMen,
      OnboardingInterestedIn.women => l10n.onboardingInterestedWomen,
      OnboardingInterestedIn.everyone => l10n.onboardingInterestedEveryone,
      _ => value,
    };
  }

  String _interestLabel(AppLocalizations l10n, String id) {
    return switch (id) {
      'music' => l10n.interestMusic,
      'travel' => l10n.interestTravel,
      'fitness' => l10n.interestFitness,
      'food' => l10n.interestFood,
      'art' => l10n.interestArt,
      'movies' => l10n.interestMovies,
      'books' => l10n.interestBooks,
      'gaming' => l10n.interestGaming,
      'nature' => l10n.interestNature,
      'photography' => l10n.interestPhotography,
      'coffee' => l10n.interestCoffee,
      'dancing' => l10n.interestDancing,
      'yoga' => l10n.interestYoga,
      'tech' => l10n.interestTech,
      'fashion' => l10n.interestFashion,
      'pets' => l10n.interestPets,
      'sports' => l10n.interestSports,
      'cooking' => l10n.interestCooking,
      _ => id,
    };
  }

  String _educationLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      OnboardingEducation.highSchool => l10n.onboardingEducationHighSchool,
      OnboardingEducation.someCollege => l10n.onboardingEducationSomeCollege,
      OnboardingEducation.bachelors => l10n.onboardingEducationBachelors,
      OnboardingEducation.masters => l10n.onboardingEducationMasters,
      OnboardingEducation.phd => l10n.onboardingEducationPhd,
      OnboardingEducation.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value,
    };
  }

  String _relationshipLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      OnboardingRelationshipGoal.longTerm => l10n.onboardingRelationshipLongTerm,
      OnboardingRelationshipGoal.shortTerm =>
        l10n.onboardingRelationshipShortTerm,
      OnboardingRelationshipGoal.friendship =>
        l10n.onboardingRelationshipFriendship,
      OnboardingRelationshipGoal.notSure => l10n.onboardingRelationshipNotSure,
      OnboardingRelationshipGoal.preferNotToSay =>
        l10n.onboardingRelationshipPreferNotToSay,
      _ => value,
    };
  }

  String _lifestyleLabel(AppLocalizations l10n, String value) {
    return switch (value) {
      OnboardingLifestyleOption.never => l10n.onboardingLifestyleNever,
      OnboardingLifestyleOption.sometimes => l10n.onboardingLifestyleSometimes,
      OnboardingLifestyleOption.regularly => l10n.onboardingLifestyleRegularly,
      OnboardingLifestyleOption.daily => l10n.onboardingLifestyleDaily,
      OnboardingLifestyleOption.none => l10n.onboardingLifestyleNone,
      OnboardingLifestyleOption.cat => l10n.onboardingLifestyleCat,
      OnboardingLifestyleOption.dog => l10n.onboardingLifestyleDog,
      OnboardingLifestyleOption.both => l10n.onboardingLifestyleBoth,
      OnboardingLifestyleOption.other => l10n.onboardingLifestyleOther,
      OnboardingLifestyleOption.preferNotToSay =>
        l10n.onboardingEducationPreferNotToSay,
      _ => value,
    };
  }
}
