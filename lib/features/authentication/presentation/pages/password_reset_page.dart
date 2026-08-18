import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/utils/validators.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_layout.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class PasswordResetPage extends StatefulWidget {
  const PasswordResetPage({super.key});

  @override
  State<PasswordResetPage> createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _emailController = TextEditingController();
  String? _emailError;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    final error = localizeAuthError(l10n, auth);
    return AuthLayout(
      title: l10n.resetPasswordTitle,
      subtitle: l10n.resetPasswordMessage,
      child: _sent
          ? MevoraEmptyState(
              icon: Icons.mark_email_read_outlined,
              title: l10n.resetEmailSentTitle,
              message: l10n.resetEmailSentMessage,
              actionLabel: l10n.backToSignIn,
              onAction: () => context.go(AppRoutes.login),
            )
          : AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MevoraTextField(
                    controller: _emailController,
                    label: l10n.email,
                    hint: l10n.emailHint,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    prefixIcon: Icons.mail_outline_rounded,
                    errorText: _emailError,
                    enabled: !auth.isBusy,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.email],
                    onChanged: (_) {
                      auth.clearError();
                      if (_emailError != null) {
                        setState(() => _emailError = null);
                      }
                    },
                    onSubmitted: (_) => unawaited(_submit()),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (error != null) ...[
                    AuthErrorBanner(message: error),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  MevoraButton(
                    label: l10n.sendResetLink,
                    isLoading: auth.isBusy,
                    onPressed: auth.isBusy
                        ? null
                        : () => unawaited(_submit()),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MevoraButton(
                    label: l10n.backToSignIn,
                    variant: MevoraButtonVariant.ghost,
                    onPressed: auth.isBusy
                        ? null
                        : () => context.go(AppRoutes.login),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final emailError = Validators.email(_emailController.text, l10n);
    setState(() => _emailError = emailError);
    if (emailError != null) {
      return;
    }
    final result = await AuthScope.of(
      context,
    ).sendPasswordReset(_emailController.text.trim());
    if (result is Success<void> && mounted) {
      setState(() => _sent = true);
    }
  }
}
