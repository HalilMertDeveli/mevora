import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Chat starter chip (MVP: widget only — not inserted into chat_page yet).
class HumorChatStarterChip extends StatefulWidget {
  const HumorChatStarterChip({
    super.key,
    required this.starter,
    this.analytics,
    this.onUsed,
  });

  final String starter;
  final AnalyticsProvider? analytics;
  final ValueChanged<String>? onUsed;

  @override
  State<HumorChatStarterChip> createState() => _HumorChatStarterChipState();
}

class _HumorChatStarterChipState extends State<HumorChatStarterChip> {
  @override
  void initState() {
    super.initState();
    final analytics = widget.analytics;
    if (analytics != null) {
      unawaited(
        analytics.logEvent(AnalyticsEvents.humorChatStarterShown),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MevoraChip(
      label: widget.starter.isEmpty ? l10n.humorChatStarter : widget.starter,
      selected: true,
      onSelected: (_) {
        final analytics = widget.analytics;
        if (analytics != null) {
          unawaited(
            analytics.logEvent(AnalyticsEvents.humorChatStarterUsed),
          );
        }
        widget.onUsed?.call(widget.starter);
      },
    );
  }
}
