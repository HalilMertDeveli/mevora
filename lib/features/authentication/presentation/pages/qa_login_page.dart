import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/app_scope.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/config/emulator_qa_login.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';

/// Emulator-only QA sign-in screen.
///
/// Deliberately plain: this is developer tooling, not product surface.
///
/// It is not an authentication bypass. The form submits through
/// `AuthScope.signIn`, the same `AuthRepository.signInWithEmail` path every
/// other email sign-in uses, so `FirebaseAuth.currentUser` ends up holding a
/// genuine Firebase Auth Emulator session and the normal router redirects take
/// over from there.
///
/// Three layers keep it out of production: the router refuses to navigate here
/// unless [EmulatorQaLogin.isEnabled], this page renders a refusal if it is
/// somehow reached anyway, and the sign-in action re-checks the gate before
/// touching any credential.
class QaLoginPage extends StatefulWidget {
  const QaLoginPage({super.key});

  @override
  State<QaLoginPage> createState() => _QaLoginPageState();
}

class _QaLoginPageState extends State<QaLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final accounts = EmulatorQaLogin.accounts;
    if (accounts.isNotEmpty) {
      _emailController.text = accounts.first.email;
      _passwordController.text = accounts.first.password;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = AppScope.of(context).config;
    if (!EmulatorQaLogin.isEnabled(config)) {
      // Belt and braces: the router already blocks this path.
      return const Scaffold(
        body: Center(child: Text('Not available.')),
      );
    }
    final auth = AuthScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('QA / Emulator Login')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Signs in against the Firebase Auth Emulator using the normal '
                'email/password path. Development builds only.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                key: const Key('qa_login_email'),
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('qa_login_password'),
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                key: const Key('qa_login_submit'),
                onPressed: auth.isBusy ? null : () => unawaited(_submit()),
                child: const Text('Sign in'),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final account in EmulatorQaLogin.accounts)
                TextButton(
                  key: Key('qa_login_preset_${account.email}'),
                  onPressed: auth.isBusy
                      ? null
                      : () {
                          setState(() {
                            _emailController.text = account.email;
                            _passwordController.text = account.password;
                          });
                        },
                  child: Text('Use ${account.label}'),
                ),
              TextButton(
                onPressed: () => context.go(AppRoutes.login),
                child: const Text('Back to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final config = AppScope.of(context).config;
    // Re-check at the action layer: being on this screen is never what
    // authorises the sign-in.
    if (!EmulatorQaLogin.isEnabled(config)) {
      return;
    }
    await AuthScope.of(context).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );
  }
}
