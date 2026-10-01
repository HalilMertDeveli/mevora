import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_durations.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/face_anchor_scope.dart';
import 'package:mevora/core/di/onboarding_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/face_anchor/presentation/controllers/face_anchor_controller.dart';
import 'package:mevora/features/face_anchor/presentation/pages/face_anchor_verify_page.dart';
import 'package:mevora/features/onboarding/domain/entities/onboarding_step.dart';
import 'package:mevora/features/face_anchor/domain/entities/face_anchor_state.dart';
import 'package:mevora/features/onboarding/presentation/controllers/onboarding_controller.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_photo_grid.dart';
import 'package:mevora/features/onboarding/presentation/widgets/onboarding_step_scaffold.dart';
import 'package:mevora/core/di/music_scope.dart';
import 'package:mevora/features/music/presentation/widgets/onboarding_music_step.dart';
import 'package:mevora/features/profile/domain/validators/person_name_validator.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_height_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_language_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_education_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_gender_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_interest_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_extended_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_lifestyle_picker.dart';
import 'package:mevora/features/profile/presentation/widgets/profile_relationship_goal_picker.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/shared/art/mevora_motion.dart';
import 'package:mevora/shared/widgets/turkish_province_picker.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';
import 'package:mevora/core/di/relationship_learning_scope.dart';
import 'package:mevora/features/relationship_learning/presentation/pages/relationship_learning_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final OnboardingController _controller;

  /// Null where Face Anchor is not wired in; the photo step then works as it
  /// did before, and the server alone decides whether the profile completes.
  FaceAnchorController? _faceAnchor;
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
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
    if (uid != null) {
      final services = FaceAnchorScope.maybeOf(context);
      if (_faceAnchor == null && services != null) {
        _faceAnchor = services.createController()
          ..addListener(_syncFaceAnchor);
      }
      _faceAnchor?.bind(uid);
    }
  }

  /// The server says whether this member needs a verified photo; the photo
  /// step asks for one only then.
  void _syncFaceAnchor() {
    final faceAnchor = _faceAnchor;
    if (!mounted || faceAnchor == null) {
      return;
    }
    _controller.setFaceAnchorRequired(faceAnchor.requirements.required);
    setState(() {});
  }

  Future<void> _verifyPhoto(OnboardingPhotoDraft draft) async {
    final faceAnchor = _faceAnchor;
    final photo = draft.remote;
    if (faceAnchor == null || photo == null) {
      return;
    }
    await FaceAnchorVerifyPage.show(
      context,
      photo: photo,
      controller: faceAnchor,
    );
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
    if (_lastNameController.text != _controller.lastName) {
      _lastNameController.text = _controller.lastName;
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
        : L10nFormat.mediumDate(AppLocalizations.of(context), _birthDate!);
    if (_birthDateLabelController.text != birthLabel) {
      _birthDateLabelController.text = birthLabel;
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) {
      _controller.removeListener(_syncFields);
    }
    _faceAnchor
      ?..removeListener(_syncFaceAnchor)
      ..dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
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
      OnboardingStep.aboutYou => _aboutYouStep(l10n),
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
      // The step body leads with the benefit headline; keep the title short.
      title: l10n.musicTitle,
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
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.givenName],
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                PersonNameValidator.maxFirstNameLength,
              ),
            ],
            onChanged: (value) => _controller.updateDraft(
              (current) => current.copyWith(displayName: value),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            controller: _lastNameController,
            label: l10n.onboardingLastName,
            helperText: l10n.onboardingLastNamePrivate,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                PersonNameValidator.maxLastNameLength,
              ),
            ],
            onChanged: _controller.updateLastName,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            readOnly: true,
            label: l10n.onboardingBirthDate,
            controller: _birthDateLabelController,
            suffixIcon: IconButton(
              tooltip: l10n.onboardingBirthDate,
              icon: const Icon(MevoraIcons.calendar),
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
            suffixIcon: const Icon(MevoraIcons.dropdown),
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
      scrollable: true,
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
      scrollable: true,
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
      subtitle: l10n.onboardingWhyRelationshipGoal,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      scrollable: true,
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
      subtitle: l10n.onboardingWhyLifestyle,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      scrollable: true,
      child: ProfileLifestylePicker(
        profile: lifestyle,
        onChanged: (next) => _controller.updateDraft(
          (current) => current.copyWith(lifestyleProfile: next),
        ),
        enabled: !_controller.isSaving,
      ),
    );
  }

  /// Optional: the same questions as Edit profile's "Get to know you".
  Widget _aboutYouStep(AppLocalizations l10n) {
    final lifestyle = _controller.profile!.lifestyleProfile;
    return OnboardingStepScaffold(
      step: OnboardingStep.aboutYou,
      title: l10n.profileEditSectionExtended,
      subtitle: l10n.onboardingAboutYouSubtitle,
      isSaving: _controller.isSaving,
      errorMessage: _controller.errorMessage,
      onBack: _controller.goBack,
      onContinue: () => unawaited(_continue()),
      scrollable: true,
      child: ProfileExtendedLifestylePicker(
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
      subtitle: l10n.onboardingWhyBio,
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
    final faceAnchor = _faceAnchor;
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
            needsFaceAnchor: _controller.needsFaceAnchor,
            faceAnchorStatusOf: faceAnchor == null
                ? null
                : (draft) => draft.remote == null
                      ? FaceAnchorPhotoStatus.none
                      : faceAnchor.statusFor(draft.remote!),
            onVerify: faceAnchor == null
                ? null
                : (draft) => unawaited(_verifyPhoto(draft)),
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
          const SizedBox(height: AppSpacing.lg),
          const Center(child: MevoraSuccessMark(size: 112)),
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.onboardingCompleteMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: context.palette.textSecondary,
            ),
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
    _birthDateLabelController.text = L10nFormat.mediumDate(
      AppLocalizations.of(context),
      picked,
    );
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
    final humorEnabled =
        AppScope.maybeOf(context)?.config.featureFlags.humorLabEnabled == true;
    final journeyAvailable =
        RelationshipLearningScope.maybeOf(context)?.journey != null;
    AuthScope.of(context).applyOnboardingComplete();

    // The first-run journey takes it from here: Humor Lab, then Relationship
    // Learning, then Picks. The server knows which step this member owes, so
    // the router sends them there now and after any restart; nothing to
    // navigate by hand.
    if (journeyAvailable) {
      return;
    }
    if (humorEnabled && mounted) {
      context.go(AppRoutes.humorCalibration);
    }
  }
}
