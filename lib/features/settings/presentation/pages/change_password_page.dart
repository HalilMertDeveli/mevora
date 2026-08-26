import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/authentication/presentation/controllers/auth_controller.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/settings/domain/validators/password_validator.dart';
import 'package:mevora/features/settings/presentation/settings_strings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _errorKey;
  var _submitting = false;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = AuthScope.of(context);
    final providers = auth.user?.authProviders;
    final hasEmailProvider = providers?.email ?? false;
    final googleOnly =
        (providers?.google ?? false) && !(providers?.email ?? false);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsChangePassword)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: googleOnly
              ? Text(l10n.settingsGooglePasswordMessage)
              : !hasEmailProvider
              ? Text(l10n.settingsGooglePasswordMessage)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MevoraTextField(
                      controller: _currentController,
                      label: l10n.settingsCurrentPassword,
                      obscureText: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    MevoraTextField(
                      controller: _newController,
                      label: l10n.settingsNewPassword,
                      obscureText: true,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    MevoraTextField(
                      controller: _confirmController,
                      label: l10n.settingsConfirmPassword,
                      obscureText: true,
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
                    if (localizeAuthError(l10n, auth) case final error?) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AuthErrorBanner(message: error),
                    ],
                    const Spacer(),
                    MevoraButton(
                      label: l10n.settingsChangePassword,
                      isLoading: _submitting,
                      onPressed: _submitting || auth.isBusy
                          ? null
                          : () => unawaited(_submit(auth)),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _submit(AuthController auth) async {
    final current = _currentController.text;
    final newPassword = _newController.text;
    final confirm = _confirmController.text;
    final currentError = PasswordValidator.validateCurrent(current);
    final newError = PasswordValidator.validateNew(newPassword);
    final confirmError = PasswordValidator.validateConfirm(
      newPassword,
      confirm,
    );
    final firstError = currentError ?? newError ?? confirmError;
    if (firstError != null) {
      setState(() => _errorKey = firstError);
      return;
    }
    setState(() {
      _submitting = true;
      _errorKey = null;
    });
    final result = await auth.changePassword(
      currentPassword: current,
      newPassword: newPassword,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    result.when(
      success: (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).settingsPasswordChanged),
          ),
        );
        context.pop();
      },
      err: (_) {},
    );
  }
}
