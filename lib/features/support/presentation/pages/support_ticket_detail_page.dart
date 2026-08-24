import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/l10n/app_localizations.dart';

class SupportTicketDetailPage extends StatelessWidget {
  const SupportTicketDetailPage({super.key, required this.ticket});

  final SupportTicket ticket;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportTicketDetailTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          _InfoRow(label: l10n.supportTicketSubject, value: ticket.subject),
          _InfoRow(
            label: l10n.supportTicketStatusLabel,
            value: _statusLabel(l10n, ticket.status),
          ),
          _InfoRow(label: l10n.supportTicketCategory, value: ticket.category),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.supportTicketMessage, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Text(ticket.message),
          if (ticket.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.supportTicketAttachments,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final path in ticket.attachments)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(path),
              ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(AppLocalizations l10n, SupportTicketStatus status) {
    return switch (status) {
      SupportTicketStatus.open => l10n.supportTicketStatusOpen,
      SupportTicketStatus.inProgress => l10n.supportTicketStatusInProgress,
      SupportTicketStatus.resolved => l10n.supportTicketStatusResolved,
      SupportTicketStatus.closed => l10n.supportTicketStatusClosed,
    };
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(value),
        ],
      ),
    );
  }
}
