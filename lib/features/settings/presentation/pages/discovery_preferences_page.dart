import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/settings_scope.dart';
import 'package:mevora/core/di/settings_services_factory.dart';
import 'package:mevora/features/profile/domain/entities/user_profile.dart';
import 'package:mevora/features/settings/domain/validators/discovery_prefs_validator.dart';
import 'package:mevora/features/settings/presentation/settings_strings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class DiscoveryPreferencesPage extends StatefulWidget {
  const DiscoveryPreferencesPage({super.key});

  @override
  State<DiscoveryPreferencesPage> createState() =>
      _DiscoveryPreferencesPageState();
}

class _DiscoveryPreferencesPageState extends State<DiscoveryPreferencesPage> {
  final _minAgeController = TextEditingController(text: '18');
  final _maxAgeController = TextEditingController(text: '99');
  final _distanceController = TextEditingController(text: '50');
  String? _showMe;
  String? _relationshipGoal;
  String? _errorKey;
  var _saving = false;

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _distanceController.dispose();
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
    return FutureBuilder<UserPreferences>(
      future: settings.settingsHub.loadDiscoveryPreferences(uid),
      builder: (context, snapshot) {
        final prefs = snapshot.data;
        if (prefs != null && _minAgeController.text == '18' && prefs.minAge != 18) {
          _minAgeController.text = '${prefs.minAge}';
          _maxAgeController.text = '${prefs.maxAge}';
          _distanceController.text = '${prefs.maxDistance}';
          _showMe = prefs.preferredGender ?? prefs.showMe;
          _relationshipGoal = prefs.relationshipGoals.firstOrNull;
        }
        return Scaffold(
          appBar: AppBar(title: Text(l10n.discoveryPreferences)),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                MevoraTextField(
                  controller: _minAgeController,
                  label: l10n.minAge,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.md),
                MevoraTextField(
                  controller: _maxAgeController,
                  label: l10n.maxAge,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.md),
                MevoraTextField(
                  controller: _distanceController,
                  label: l10n.maxDistance,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _showMe,
                  decoration: InputDecoration(labelText: l10n.filterGender),
                  items: [
                    for (final value in const ['woman', 'man', 'everyone'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(SettingsStrings.genderLabel(l10n, value)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _showMe = value),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  value: _relationshipGoal,
                  decoration: InputDecoration(
                    labelText: l10n.filterRelationshipGoal,
                  ),
                  items: [
                    for (final value
                        in const ['longTerm', 'casual', 'figuringOut'])
                      DropdownMenuItem(
                        value: value,
                        child: Text(
                          SettingsStrings.relationshipGoalLabel(l10n, value),
                        ),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _relationshipGoal = value),
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
                  label: l10n.applyFilters,
                  isLoading: _saving,
                  onPressed: _saving
                      ? null
                      : () => unawaited(_save(uid, settings)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save(String uid, SettingsServices settings) async {
    final prefs = UserPreferences(
      uid: uid,
      preferredGender: _showMe,
      showMe: _showMe,
      minAge: int.tryParse(_minAgeController.text) ?? 18,
      maxAge: int.tryParse(_maxAgeController.text) ?? 99,
      maxDistance: int.tryParse(_distanceController.text) ?? 50,
      relationshipGoals: _relationshipGoal == null
          ? const []
          : [_relationshipGoal!],
    );
    final validation = DiscoveryPrefsValidator.validate(prefs);
    if (validation != null) {
      setState(() => _errorKey = validation);
      return;
    }
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    await settings.settingsHub.saveDiscoveryPreferences(prefs);
    if (mounted) {
      setState(() => _saving = false);
      context.pop();
    }
  }
}
