import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/utils/validators.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_layout.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_legal_footer.dart';
import 'package:mevora/features/authentication/presentation/widgets/social_auth_buttons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
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
    final busyProvider = switch (auth.status) {
      Authenticating(:final provider) => provider,
      _ => null,
    };
    return AuthLayout(
      title: l10n.createAccountTitle,
      subtitle: l10n.registerSubtitle,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MevoraTextField(
              controller: _emailController,
              label: l10n.email,
              hint: l10n.emailHint,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
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
            ),
            const SizedBox(height: AppSpacing.md),
            MevoraTextField(
              controller: _passwordController,
              label: l10n.password,
              helperText: l10n.passwordMinLength(8),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.lock_outline_rounded,
              errorText: _passwordError,
              enabled: !auth.isBusy,
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
              enabled: !auth.isBusy,
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
            const SizedBox(height: AppSpacing.lg),
            if (error != null) ...[
              AuthErrorBanner(message: error),
              const SizedBox(height: AppSpacing.sm),
            ],
            MevoraButton(
              label: l10n.createAccount,
              isLoading: auth.isBusy && busyProvider == 'email',
              onPressed: auth.isBusy ? null : () => unawaited(_submit()),
            ),
            AuthLegalFooter(
              onTerms: () => context.push(AppRoutes.legalTerms),
              onPrivacy: () => context.push(AppRoutes.legalPrivacy),
            ),
            const SizedBox(height: AppSpacing.lg),
            SocialAuthButtons(
              enabled: !auth.isBusy,
              busyProvider: busyProvider,
              onGoogle: () => unawaited(auth.signInWithGoogle()),
              onApple: () => unawaited(auth.signInWithApple()),
              onSpotify: () => unawaited(auth.signInWithSpotify()),
              onPhone: () => context.push(AppRoutes.phone),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.alreadyHaveAccount,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                MevoraButton(
                  label: l10n.signIn,
                  variant: MevoraButtonVariant.ghost,
                  isExpanded: false,
                  onPressed: auth.isBusy
                      ? null
                      : () => context.go(AppRoutes.login),
                ),
              ],
            ),
          ],
        ),
      ),
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
    await AuthScope.of(context).register(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }
}
