import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/core/utils/phone_mask.dart';
import 'package:mevora/features/authentication/presentation/auth_error_text.dart';
import 'package:mevora/features/authentication/presentation/widgets/country_dial_codes.dart';
import 'package:mevora/features/authentication/presentation/widgets/phone_number_input.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

class PhoneSignInPage extends StatefulWidget {
  const PhoneSignInPage({super.key});

  @override
  State<PhoneSignInPage> createState() => _PhoneSignInPageState();
}

class _PhoneSignInPageState extends State<PhoneSignInPage> {
  final _controller = TextEditingController();
  CountryDialCode _country = CountryDialCodes.turkey;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.phoneTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.phoneSubtitle,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: AppSpacing.lg),
              PhoneNumberInput(
                country: _country,
                controller: _controller,
                errorText: _error ?? localizeAuthError(l10n, auth),
                onCountrySelected: (country) {
                  setState(() {
                    _country = country;
                    _error = null;
                  });
                },
                onSubmitted: (_) => unawaited(_submit()),
              ),
              const Spacer(),
              MevoraButton(
                label: l10n.sendCode,
                isLoading: auth.isBusy,
                onPressed: auth.isBusy ? null : () => unawaited(_submit()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final e164 = PhoneMask.e164(_country.dialCode, _controller.text);
    if (!PhoneMask.isValidE164(e164)) {
      setState(() => _error = l10n.authInvalidPhone);
      return;
    }
    setState(() => _error = null);
    await AuthScope.of(context).sendPhoneCode(e164);
    if (!mounted) {
      return;
    }
    if (AuthScope.of(context).phoneChallenge != null) {
      context.go(AppRoutes.phoneOtp);
    }
  }
}
