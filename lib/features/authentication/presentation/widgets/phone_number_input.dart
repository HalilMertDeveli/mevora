import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/authentication/presentation/widgets/country_dial_codes.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class CountrySelectorButton extends StatelessWidget {
  const CountrySelectorButton({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CountryDialCode selected;
  final ValueChanged<CountryDialCode> onSelected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        final next = await _pick(context);
        if (next != null) {
          onSelected(next);
        }
      },
      child: Text('${selected.flag} +${selected.dialCode}'),
    );
  }

  Future<CountryDialCode?> _pick(BuildContext context) {
    return MevoraBottomSheet.show<CountryDialCode>(
      context,
      child: _CountryPickerSheet(selected: selected),
    );
  }
}

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.selected});

  final CountryDialCode selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = CountryDialCodes.all.where((country) {
      final q = _query.toLowerCase();
      return country.name.toLowerCase().contains(q) ||
          country.dialCode.contains(q) ||
          country.iso2.toLowerCase().contains(q);
    }).toList();

    return SizedBox(
      height: 420,
      child: Column(
        children: [
          MevoraTextField(
            hint: AppLocalizations.of(context).countrySearchHint,
            prefixIcon: Icons.search,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final country = filtered[index];
                return ListTile(
                  leading: Text(country.flag, style: const TextStyle(fontSize: 22)),
                  title: Text(country.name),
                  trailing: Text('+${country.dialCode}'),
                  selected: country.iso2 == widget.selected.iso2 &&
                      country.dialCode == widget.selected.dialCode,
                  onTap: () => Navigator.of(context).pop(country),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class PhoneNumberInput extends StatelessWidget {
  const PhoneNumberInput({
    super.key,
    required this.country,
    required this.controller,
    required this.onCountrySelected,
    this.errorText,
    this.onSubmitted,
  });

  final CountryDialCode country;
  final TextEditingController controller;
  final ValueChanged<CountryDialCode> onCountrySelected;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 108,
          child: CountrySelectorButton(
            selected: country,
            onSelected: onCountrySelected,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: MevoraTextField(
            controller: controller,
            label: AppLocalizations.of(context).phoneNumber,
            hint: AppLocalizations.of(context).phoneHint,
            keyboardType: TextInputType.phone,
            prefixIcon: Icons.phone_outlined,
            errorText: errorText,
            onSubmitted: onSubmitted,
          ),
        ),
      ],
    );
  }
}
