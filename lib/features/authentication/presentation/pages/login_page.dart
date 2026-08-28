import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_typography.dart';
import 'package:mevora/core/utils/validators.dart';
import 'package:mevora/features/authentication/domain/entities/auth_status.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_error_banner.dart';
import 'package:mevora/features/authentication/presentation/widgets/auth_legal_footer.dart';
import 'package:mevora/features/authentication/presentation/widgets/login_hero_background.dart';
import 'package:mevora/features/authentication/presentation/widgets/welcome_auth_buttons.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/components/mevora_logo.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController = ScrollController();
  final _emailSectionKey = GlobalKey();

  late final AnimationController _entry;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _sloganOpacity;
  late final Animation<Offset> _sloganSlide;
  late final Animation<double> _buttonsOpacity;
  late final Animation<Offset> _buttonsSlide;

  bool _obscurePassword = true;
  bool _showEmailForm = false;
  String? _emailError;
  String? _passwordError;
  bool _viewLogged = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _logoOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.0, 0.45, curve: Curves.easeOut),
    );
    _sloganOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.15, 0.6, curve: Curves.easeOut),
    );
    _sloganSlide = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.15, 0.65, curve: Curves.easeOutCubic),
      ),
    );
    _buttonsOpacity = CurvedAnimation(
      parent: _entry,
      curve: const Interval(0.35, 1.0, curve: Curves.easeOut),
    );
    _buttonsSlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entry,
        curve: const Interval(0.35, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    unawaited(_entry.forward());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewLogged) {
      _viewLogged = true;
      unawaited(AuthScope.of(context).reportLoginScreenViewed());
    }
  }

  @override
  void dispose() {
    _entry.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _revealEmailForm() async {
    setState(() => _showEmailForm = true);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final ctx = _emailSectionKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final error = localizeAuthError(l10n, auth);
    final busyProvider = switch (auth.status) {
      Authenticating(:final provider) => provider,
      _ => null,
    };
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      body: LoginHeroBackground(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: _entry,
            builder: (context, _) {
              return ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.lg,
                  AppSpacing.screenPadding,
                  AppSpacing.lg + bottomInset,
                ),
                children: [
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.06),
                  FadeTransition(
                    opacity: _logoOpacity,
                    child: MevoraLogo(
                      size: 72,
                      onDark: theme.brightness == Brightness.dark,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FadeTransition(
                    opacity: _sloganOpacity,
                    child: SlideTransition(
                      position: _sloganSlide,
                      child: Text(
                        l10n.loginSlogan,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontFamily: AppTypography.displayFontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: MediaQuery.sizeOf(context).height * 0.08),
                  FadeTransition(
                    opacity: _buttonsOpacity,
                    child: SlideTransition(
                      position: _buttonsSlide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (error != null) ...[
                            AuthErrorBanner(message: error),
                            const SizedBox(height: AppSpacing.md),
                          ],
                          WelcomeAuthButtons(
                            enabled: !auth.isBusy,
                            busyProvider: busyProvider,
                            onGoogle: () =>
                                unawaited(auth.signInWithGoogle()),
                            onApple: () => unawaited(auth.signInWithApple()),
                            onPhone: () => context.push(AppRoutes.phone),
                            onSpotify: () =>
                                unawaited(auth.signInWithSpotify()),
                            onEmail: () => unawaited(_revealEmailForm()),
                          ),
                          Theme(
                            data: theme,
                            child: AuthLegalFooter(
                              onTerms: () => context.push(AppRoutes.legalTerms),
                              onPrivacy: () =>
                                  context.push(AppRoutes.legalPrivacy),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_showEmailForm) ...[
                    const SizedBox(height: AppSpacing.xl),
                    KeyedSubtree(
                      key: _emailSectionKey,
                      child: _EmailSignInPanel(
                        emailController: _emailController,
                        passwordController: _passwordController,
                        obscurePassword: _obscurePassword,
                        emailError: _emailError,
                        passwordError: _passwordError,
                        busy: auth.isBusy,
                        emailLoading:
                            auth.isBusy && busyProvider == 'email',
                        onToggleObscure: () {
                          setState(
                            () => _obscurePassword = !_obscurePassword,
                          );
                        },
                        onClearFieldErrors: () {
                          auth.clearError();
                          if (_emailError != null || _passwordError != null) {
                            setState(() {
                              _emailError = null;
                              _passwordError = null;
                            });
                          }
                        },
                        onForgotPassword: () =>
                            context.push(AppRoutes.passwordReset),
                        onSubmit: () => unawaited(_submit()),
                        onCreateAccount: () =>
                            context.go(AppRoutes.register),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
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

class _EmailSignInPanel extends StatelessWidget {
  const _EmailSignInPanel({
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.emailError,
    required this.passwordError,
    required this.busy,
    required this.emailLoading,
    required this.onToggleObscure,
    required this.onClearFieldErrors,
    required this.onForgotPassword,
    required this.onSubmit,
    required this.onCreateAccount,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final String? emailError;
  final String? passwordError;
  final bool busy;
  final bool emailLoading;
  final VoidCallback onToggleObscure;
  final VoidCallback onClearFieldErrors;
  final VoidCallback onForgotPassword;
  final VoidCallback onSubmit;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return DecoratedBox(
      decoration: AppDecorations.glassCard(
        brightness: Theme.of(context).brightness,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.signInWithEmail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? AppColors.primaryText
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              MevoraTextField(
                controller: emailController,
                label: l10n.email,
                hint: l10n.emailHint,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                prefixIcon: Icons.mail_outline_rounded,
                errorText: emailError,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.email],
                onChanged: (_) => onClearFieldErrors(),
              ),
              const SizedBox(height: AppSpacing.md),
              MevoraTextField(
                controller: passwordController,
                label: l10n.password,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.lock_outline_rounded,
                errorText: passwordError,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                suffixIcon: IconButton(
                  tooltip: obscurePassword
                      ? l10n.showPassword
                      : l10n.hidePassword,
                  onPressed: onToggleObscure,
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
                onSubmitted: (_) => onSubmit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: MevoraButton(
                  label: l10n.forgotPassword,
                  variant: MevoraButtonVariant.ghost,
                  isExpanded: false,
                  onPressed: busy ? null : onForgotPassword,
                ),
              ),
              MevoraButton(
                label: l10n.signIn,
                isLoading: emailLoading,
                onPressed: busy ? null : onSubmit,
              ),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l10n.newToMevora,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.secondaryText,
                    ),
                  ),
                  MevoraButton(
                    label: l10n.createAnAccount,
                    variant: MevoraButtonVariant.ghost,
                    isExpanded: false,
                    onPressed: busy ? null : onCreateAccount,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
