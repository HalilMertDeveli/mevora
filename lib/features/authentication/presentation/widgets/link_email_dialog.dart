import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/utils/validators.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

Future<void> showLinkEmailDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _LinkEmailDialog(),
  );
}

class _LinkEmailDialog extends StatefulWidget {
  const _LinkEmailDialog();

  @override
  State<_LinkEmailDialog> createState() => _LinkEmailDialogState();
}

class _LinkEmailDialogState extends State<_LinkEmailDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    final error = localizeAuthError(l10n, auth);
    return AlertDialog(
      title: Text(l10n.linkEmailTitle),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.linkEmailSubtitle),
              const SizedBox(height: AppSpacing.md),
              if (error != null) ...[
                AuthErrorBanner(message: error),
                const SizedBox(height: AppSpacing.md),
              ],
              MevoraTextField(
                controller: _emailController,
                label: l10n.email,
                hint: l10n.emailHint,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: Icons.mail_outline_rounded,
                errorText: _emailError,
                enabled: !_submitting,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                onChanged: (_) {
                  auth.clearError();
                  if (_emailError != null) {
                    setState(() => _emailError = null);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              MevoraTextField(
                controller: _passwordController,
                label: l10n.password,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.next,
                prefixIcon: Icons.lock_outline_rounded,
                errorText: _passwordError,
                enabled: !_submitting,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                suffixIcon: IconButton(
                  tooltip: _obscurePassword
                      ? l10n.showPassword
                      : l10n.hidePassword,
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                onChanged: (_) {
                  auth.clearError();
                  if (_passwordError != null) {
                    setState(() => _passwordError = null);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              MevoraTextField(
                controller: _confirmController,
                label: l10n.confirmPassword,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.lock_outline_rounded,
                errorText: _confirmError,
                enabled: !_submitting,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) {
                  if (_confirmError != null) {
                    setState(() => _confirmError = null);
                  }
                },
                onSubmitted: (_) => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
      actions: [
        MevoraButton(
          label: l10n.cancel,
          variant: MevoraButtonVariant.ghost,
          isExpanded: false,
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        ),
        MevoraButton(
          label: l10n.link,
          isExpanded: false,
          isLoading: _submitting,
          onPressed: _submitting ? null : () => unawaited(_submit()),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final emailError = Validators.email(_emailController.text, l10n);
    final passwordError = Validators.password(_passwordController.text, l10n);
    final confirmError = Validators.confirmPassword(
      _confirmController.text,
      _passwordController.text,
      l10n,
    );
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _confirmError = confirmError;
    });
    if (emailError != null || passwordError != null || confirmError != null) {
      return;
    }
    setState(() => _submitting = true);
    final result = await AuthScope.of(context).linkEmail(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
    if (!mounted) {
      return;
    }
    setState(() => _submitting = false);
    if (result is Success<void>) {
      Navigator.of(context).pop();
    }
  }
}
