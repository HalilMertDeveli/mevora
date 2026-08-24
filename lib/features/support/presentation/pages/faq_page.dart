import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/support/domain/content/support_content.dart';
import 'package:mevora/l10n/app_localizations.dart';

class FaqPage extends StatefulWidget {
  const FaqPage({super.key, this.initialCategory});

  final String? initialCategory;

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = SupportContent.faqEntries(l10n)
        .where((entry) {
          final category = widget.initialCategory;
          if (category != null && category.isNotEmpty && entry.categoryId != category) {
            return false;
          }
          if (_query.trim().isEmpty) {
            return true;
          }
          final needle = _query.trim().toLowerCase();
          return entry.question.toLowerCase().contains(needle) ||
              entry.answer.toLowerCase().contains(needle);
        })
        .toList(growable: false);
    final title = widget.initialCategory == null || widget.initialCategory!.isEmpty
        ? l10n.supportFaqTitle
        : SupportContent.faqCategoryLabel(l10n, widget.initialCategory!);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: l10n.supportFaqSearchHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(l10n.supportFaqEmpty))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenPadding,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: ExpansionTile(
                          title: Text(entry.question),
                          subtitle: Text(
                            SupportContent.faqCategoryLabel(
                              l10n,
                              entry.categoryId,
                            ),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
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
                                child: Text(entry.answer),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.supportTicketCreate),
        icon: const Icon(Icons.support_agent_outlined),
        label: Text(l10n.supportCreateTicket),
      ),
    );
  }
}
