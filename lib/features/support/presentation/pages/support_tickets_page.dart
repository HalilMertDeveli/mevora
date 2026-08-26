import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/core/routing/app_routes.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_empty_state.dart';

class SupportTicketsPage extends StatelessWidget {
  const SupportTicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final uid = AuthScope.of(context).user?.id;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.supportMyTickets)),
        body: Center(child: Text(l10n.needSignIn)),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportMyTickets)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.supportTicketCreate),
        icon: const Icon(Icons.add),
        label: Text(l10n.supportCreateTicket),
      ),
      body: StreamBuilder(
        stream: SupportScope.of(context).repository.watchTickets(uid),
        builder: (context, snapshot) {
          final tickets = snapshot.data ?? const <SupportTicket>[];
          if (tickets.isEmpty) {
            return MevoraEmptyState(
              icon: Icons.support_agent_outlined,
              title: l10n.supportTicketsEmptyTitle,
              message: l10n.supportTicketsEmptyMessage,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            itemCount: tickets.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final ticket = tickets[index];
              return Card(
                child: ListTile(
                  title: Text(ticket.subject),
                  subtitle: Text(
                    '${_statusLabel(l10n, ticket.status)}\n${ticket.message}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(
                    AppRoutes.supportTicketDetailPath(ticket.id),
                    extra: ticket,
                  ),
                ),
              );
            },
          );
        },
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
