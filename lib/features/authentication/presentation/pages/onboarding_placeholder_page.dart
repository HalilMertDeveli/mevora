import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

class OnboardingPlaceholderPage extends StatelessWidget {
  const OnboardingPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: MevoraEmptyState(
          icon: Icons.auto_awesome_outlined,
          title: l10n.onboardingTitle,
          message: l10n.onboardingMessage,
          actionLabel: l10n.logOut,
          onAction: auth.isBusy ? null : () => unawaited(auth.signOut()),
        ),
      ),
    );
  }
}
