import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/utils/validators.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_layout.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_legal_footer.dart';
import 'package:mevora/features/authentication/presentation/widgets/social_auth_buttons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _showEmail = false;
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final config = AppScope.of(context).config;
    final l10n = AppLocalizations.of(context);
    final error = localizeAuthError(l10n, auth);
    final busyProvider = switch (auth.status) {
      Authenticating(:final provider) => provider,
      _ => null,
    };

    return AuthLayout(
      title: l10n.appName,
      subtitle: l10n.connectTagline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (error != null) ...[
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          SocialAuthButtons(
            enabled: !auth.isBusy,
            busyProvider: busyProvider,
            onGoogle: () => unawaited(auth.signInWithGoogle()),
            onApple: () => unawaited(auth.signInWithApple()),
            onSpotify: () => unawaited(auth.signInWithSpotify()),
            onPhone: () => context.push(AppRoutes.phone),
          ),
          AuthLegalFooter(
            onTerms: () => unawaited(
              launchUrl(Uri.parse(config.termsOfServiceUrl)),
            ),
            onPrivacy: () => unawaited(
              launchUrl(Uri.parse(config.privacyPolicyUrl)),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraButton(
            label: l10n.signInWithEmail,
            variant: MevoraButtonVariant.ghost,
            onPressed: () => setState(() => _showEmail = !_showEmail),
          ),
          if (_showEmail) ...[
            const SizedBox(height: AppSpacing.md),
            MevoraTextField(
              controller: _emailController,
              label: l10n.email,
              hint: l10n.emailHint,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: Icons.mail_outline_rounded,
              errorText: _emailError,
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
              textInputAction: TextInputAction.done,
              prefixIcon: Icons.lock_outline_rounded,
              errorText: _passwordError,
              autofillHints: const [AutofillHints.password],
              suffixIcon: IconButton(
                tooltip: _obscurePassword ? l10n.showPassword : l10n.hidePassword,
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
              onSubmitted: (_) => unawaited(_submit()),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: MevoraButton(
                label: l10n.forgotPassword,
                variant: MevoraButtonVariant.ghost,
                isExpanded: false,
                onPressed: auth.isBusy
                    ? null
                    : () => context.push(AppRoutes.passwordReset),
              ),
            ),
            MevoraButton(
              label: l10n.signIn,
              isLoading: auth.isBusy && busyProvider == 'email',
              onPressed: auth.isBusy ? null : () => unawaited(_submit()),
            ),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.newToMevora,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                MevoraButton(
                  label: l10n.createAnAccount,
                  variant: MevoraButtonVariant.ghost,
                  isExpanded: false,
                  onPressed: auth.isBusy
                      ? null
                      : () => context.go(AppRoutes.register),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final emailError = Validators.email(_emailController.text, l10n);
    final passwordError = Validators.password(_passwordController.text, l10n);
    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
    });
    if (emailError != null || passwordError != null) {
      return;
    }
    await AuthScope.of(context).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }
}
