import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

/// Manual city path when location is denied. Never blocks the rest of the app.
abstract final class ManualCitySheet {
  static Future<String?> show(BuildContext context, {String? initialCity}) {
    return MevoraBottomSheet.show<String>(
      context,
      title: AppLocalizations.of(context).onboardingCity,
      child: _ManualCityForm(initialCity: initialCity),
    );
  }
}

class _ManualCityForm extends StatefulWidget {
  const _ManualCityForm({this.initialCity});

  final String? initialCity;

  @override
  State<_ManualCityForm> createState() => _ManualCityFormState();
}

class _ManualCityFormState extends State<_ManualCityForm> {
  late final TextEditingController _city;

  @override
  void initState() {
    super.initState();
    _city = TextEditingController(text: widget.initialCity ?? '');
  }

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _city.text.trim();
    if (value.isEmpty) {
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MevoraTextField(
          controller: _city,
          label: l10n.onboardingCity,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: AppSpacing.md),
        MevoraButton(
          label: l10n.continueAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
