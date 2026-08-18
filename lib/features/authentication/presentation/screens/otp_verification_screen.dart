import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/otp_code_input.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({super.key});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final phone = AuthScope.of(context).phoneAuth;
      phone.restoreOrReset();
      if (!phone.hasActiveChallenge) {
        context.go(AppRoutes.phone);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final phone = AuthScope.of(context).phoneAuth;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: phone,
      builder: (context, _) {
        if (phone.state is PhoneAuthenticated) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              // AuthController snapshot routes to onboarding or discovery.
            }
          });
        }
        final challenge = switch (phone.state) {
          OtpSent(:final challenge) => challenge,
          VerifyingOtp(:final challenge) => challenge,
          OtpError(:final challenge) => challenge,
          _ => null,
        };
        final verifying = phone.state is VerifyingOtp;
        final error = localizePhoneError(l10n, phone.state);
        final success = phone.state is PhoneAuthenticated;
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: l10n.back,
              onPressed: () {
                phone.resetToPhoneEntry();
                context.go(AppRoutes.phone);
              },
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                Text(
                  l10n.otpTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.otpSentTo(challenge?.maskedPhone ?? ''),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                Semantics(
                  label: l10n.otpFieldLabel,
                  child: OtpCodeInput(
                    enabled: !verifying,
                    onChanged: (_) {},
                    onCompleted: (code) => unawaited(phone.verify(code)),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    error,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (verifying)
                  MevoraLoading(message: l10n.verifying)
                else if (success)
                  MevoraLoading(message: l10n.phoneVerifiedSuccess)
                else if (phone.resendSeconds > 0)
                  Text(
                    l10n.resendCountdown(phone.resendSeconds),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  MevoraButton(
                    label: l10n.resend,
                    variant: MevoraButtonVariant.secondary,
                    onPressed: phone.canResend
                        ? () => unawaited(phone.resend())
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
