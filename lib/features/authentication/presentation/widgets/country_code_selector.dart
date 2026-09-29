import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/authentication/domain/entities/country_code.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_bottom_sheet.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class CountryCodeSelector extends StatelessWidget {
  const CountryCodeSelector({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  final CountryCode selected;
  final ValueChanged<CountryCode> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      button: true,
      label: '${l10n.countryCode} ${selected.flag} ${selected.dialPrefix}',
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          // Matches the text field beside it, so the pair reads as one input.
          minimumSize: const Size(96, 56),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          side: BorderSide(color: context.palette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
        onPressed: () async {
          final next = await MevoraBottomSheet.show<CountryCode>(
            context,
            title: l10n.countryCode,
            child: _CountryCodePickerSheet(selected: selected),
          );
          if (next != null) {
            onSelected(next);
          }
        },
        child: Text('${selected.flag} ${selected.dialPrefix}'),
      ),
    );
  }
}

class _CountryCodePickerSheet extends StatefulWidget {
  const _CountryCodePickerSheet({required this.selected});

  final CountryCode selected;

  @override
  State<_CountryCodePickerSheet> createState() =>
      _CountryCodePickerSheetState();
}

class _CountryCodePickerSheetState extends State<_CountryCodePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = CountryCodes.all.where((country) {
      final q = _query.toLowerCase();
      return country.country.toLowerCase().contains(q) ||
          country.dialCode.contains(q) ||
          country.isoCode.toLowerCase().contains(q);
    }).toList();

    return SizedBox(
      // Tall enough to browse, short enough to leave the keyboard room.
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        children: [
          MevoraTextField(
            hint: AppLocalizations.of(context).countrySearchHint,
            prefixIcon: MevoraIcons.search,
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final country = filtered[index];
                return Semantics(
                  button: true,
                  label: '${country.country} ${country.dialPrefix}',
                  child: ListTile(
                    leading: Text(
                      country.flag,
                      style: const TextStyle(fontSize: 22),
                    ),
                    title: Text(country.country),
                    trailing: Text(country.dialPrefix),
                    selected: country.isoCode == widget.selected.isoCode,
                    onTap: () => Navigator.of(context).pop(country),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
