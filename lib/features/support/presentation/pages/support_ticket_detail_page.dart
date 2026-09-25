import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_error_view.dart';
import 'package:mevora/shared/widgets/mevora_loading.dart';

/// Support ticket detail.
///
/// [ticket] is the in-memory object handed over by the tickets list. It is
/// absent for direct/deep-link navigation, in which case the page resolves
/// [ticketId] through [SupportRepository.getTicket] and renders a real
/// not-found state when the ticket does not exist or is not owned by the
/// signed-in user. No placeholder ticket is ever constructed.
class SupportTicketDetailPage extends StatefulWidget {
  const SupportTicketDetailPage({
    super.key,
    required this.ticketId,
    this.ticket,
  });

  final String ticketId;
  final SupportTicket? ticket;

  @override
  State<SupportTicketDetailPage> createState() =>
      _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState extends State<SupportTicketDetailPage> {
  SupportTicket? _ticket;
  bool _isLoading = false;
  bool _notFound = false;
  bool _resolveScheduled = false;

  @override
  void initState() {
    super.initState();
    _ticket = widget.ticket;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ticket == null && !_resolveScheduled) {
      _resolveScheduled = true;
      unawaited(_resolve());
    }
  }

  Future<void> _resolve() async {
    final uid = AuthScope.of(context).user?.id;
    final repository = SupportScope.maybeOf(context)?.repository;
    if (uid == null || uid.isEmpty || repository == null) {
      setState(() {
        _isLoading = false;
        _notFound = true;
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _notFound = false;
    });
    try {
      final resolved = await repository.getTicket(
        userId: uid,
        ticketId: widget.ticketId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _ticket = resolved;
        _isLoading = false;
        _notFound = resolved == null;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      // Transport/permission failure: offer a retry instead of a
      // not-found state, which would be misleading.
      setState(() {
        _isLoading = false;
        _notFound = false;
      });
    }
  }

  void _retry() {
    _resolveScheduled = true;
    unawaited(_resolve());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ticket = _ticket;
    if (ticket == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.supportTicketDetailTitle)),
        body: SafeArea(
          child: _isLoading
              ? MevoraLoading.page(message: l10n.loading)
              : MevoraErrorView(
                  icon: _notFound
                      ? Icons.search_off_rounded
                      : Icons.error_outline_rounded,
                  title: _notFound
                      ? l10n.supportTicketNotFoundTitle
                      : l10n.somethingWentWrong,
                  message: _notFound
                      ? l10n.supportTicketNotFoundMessage
                      : l10n.unexpectedError,
                  onRetry: _notFound ? null : _retry,
                ),
        ),
      );
    }
    return _SupportTicketDetailView(ticket: ticket);
  }
}

class _SupportTicketDetailView extends StatelessWidget {
  const _SupportTicketDetailView({required this.ticket});

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
