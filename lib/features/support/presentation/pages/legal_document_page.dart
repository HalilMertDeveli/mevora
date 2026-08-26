import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.sections,
    this.intro,
  });

  final String title;
  final String? intro;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          if (intro != null && intro!.isNotEmpty) ...[
            Text(intro!, style: theme.textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.lg),
          ],
          for (final section in sections)
            _LegalSectionTile(
              title: section.title,
              body: section.body,
            ),
        ],
      ),
    );
  }
}

class _LegalSectionTile extends StatelessWidget {
  const _LegalSectionTile({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ExpansionTile(
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(body, style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        ],
      ),
    );
  }
}
