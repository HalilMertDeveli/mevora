import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/authentication/domain/entities/phone_auth_state.dart';
import 'package:mevora/features/authentication/domain/services/e164_formatter.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/controllers/phone_auth_controller.dart';
import 'package:mevora/features/authentication/presentation/widgets/country_code_selector.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = AuthScope.of(context).phoneAuth;
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: phone,
      builder: (context, _) {
        final sending = phone.state is SendingOtp;
        final blocked = phone.state is TooManyAttempts;
        final error = localizePhoneError(l10n, phone.state);
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: l10n.back,
              onPressed: () => context.go(AppRoutes.login),
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.screenPadding),
              children: [
                Text(
                  l10n.phoneTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.phoneSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CountryCodeSelector(
                      selected: phone.country,
                      onSelected: phone.selectCountry,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Semantics(
                        textField: true,
                        label: l10n.phoneNumber,
                        child: MevoraTextField(
                          controller: _controller,
                          label: l10n.phoneNumber,
                          hint: l10n.phoneHint,
                          keyboardType: TextInputType.phone,
                          errorText: error,
                          enabled: !sending,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[\d\s\-\(\)]'),
                            ),
                          ],
                          onChanged: (value) => _onChanged(phone, value),
                          onSubmitted: (_) => unawaited(_submit()),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${phone.country.dialPrefix} ${phone.formattedNational.isEmpty ? '—' : phone.formattedNational}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (sending)
                  MevoraLoading(message: l10n.sendingSms)
                else ...[
                  if (error != null) ...[
                    Text(
                      error,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  MevoraButton(
                    label: l10n.sendCode,
                    onPressed: blocked ? null : () => unawaited(_submit()),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _onChanged(PhoneAuthController phone, String value) {
    phone.updateNationalNumber(value);
    final formatted = E164Formatter.formatNational(phone.country, value);
    if (formatted != _controller.text) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  Future<void> _submit() async {
    final sent = await AuthScope.of(context).phoneAuth.sendCode();
    if (sent && mounted) {
      context.go(AppRoutes.phoneOtp);
    }
  }
}
