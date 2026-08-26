import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/otp_code_input.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class OtpVerificationPage extends StatefulWidget {
  const OtpVerificationPage({super.key});

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  String _code = '';

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final challenge = auth.phoneChallenge;
    final l10n = AppLocalizations.of(context);
    final error = localizeAuthError(l10n, auth);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            auth.returnToLogin();
            context.go(AppRoutes.login);
          },
        ),
        title: Text(l10n.otpTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.otpTitle,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.otpSentTo(challenge?.maskedPhone ?? ''),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      OtpCodeInput(
                        enabled: !auth.isBusy,
                        onChanged: (value) => _code = value,
                        onCompleted: (value) =>
                            unawaited(auth.verifyPhoneCode(value)),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          error,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      if (auth.resendSeconds > 0)
                        Text(
                          l10n.resendCountdown(auth.resendSeconds),
                          textAlign: TextAlign.center,
                        )
                      else
                        MevoraButton(
                          label: l10n.resend,
                          variant: MevoraButtonVariant.ghost,
                          onPressed: auth.isBusy
                              ? null
                              : () => unawaited(auth.resendPhoneCode()),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              MevoraButton(
                label: l10n.verify,
                isLoading: auth.isBusy,
                onPressed: auth.isBusy
                    ? null
                    : () => unawaited(auth.verifyPhoneCode(_code)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
