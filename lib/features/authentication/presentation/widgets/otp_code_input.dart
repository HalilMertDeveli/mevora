import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/utils/otp_validator.dart';
import 'package:mevora/l10n/app_localizations.dart';

class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    required this.onChanged,
    this.onCompleted,
    this.enabled = true,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onCompleted;
  final bool enabled;

  @override
  State<OtpCodeInput> createState() => _OtpCodeInputState();
}

class _OtpCodeInputState extends State<OtpCodeInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digits = OtpValidator.digitsOnly(_controller.text);
    return Semantics(
      label: AppLocalizations.of(context).otpFieldLabel,
      textField: true,
      child: AutofillGroup(
        child: GestureDetector(
          onTap: () => _focusNode.requestFocus(),
          child: Stack(
          children: [
            Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                enableSuggestions: false,
                autocorrect: false,
                smartDashesType: SmartDashesType.disabled,
                smartQuotesType: SmartQuotesType.disabled,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(OtpValidator.length),
                ],
                onChanged: (value) {
                  final next = OtpValidator.digitsOnly(value);
                  widget.onChanged(next);
                  setState(() {});
                  if (OtpValidator.isComplete(next)) {
                    widget.onCompleted?.call(next);
                  }
                },
              ),
            ),
            Row(
              children: List.generate(OtpValidator.length, (index) {
                final filled = index < digits.length;
                final char = filled ? digits[index] : '';
                final focused = index == digits.length && _focusNode.hasFocus;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                      border: Border.all(
                        color: focused
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: focused ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      char,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
