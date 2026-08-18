import 'package:flutter/material.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

class FeaturePlaceholderPage extends StatelessWidget {
  const FeaturePlaceholderPage({
    super.key,
    required this.title,
    this.message,
    this.detail,
  });

  final String title;
  final String? message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final body = message ?? l10n.comingSoon;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: MevoraEmptyState(
        title: title,
        message: detail == null ? body : '$body\n$detail',
      ),
    );
  }
}
