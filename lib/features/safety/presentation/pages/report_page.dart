import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/core/di/social_scope.dart';
import 'package:mevora/features/safety/domain/models/report_reason.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_dialog.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

String reportReasonLabel(AppLocalizations l10n, ReportReason reason) {
  return switch (reason) {
    ReportReason.spam => l10n.reportSpam,
    ReportReason.harassment => l10n.reportHarassment,
    ReportReason.inappropriateContent => l10n.reportInappropriate,
    ReportReason.scam => l10n.reportScam,
    ReportReason.fakeProfile => l10n.reportFakeProfile,
    ReportReason.underage => l10n.reportUnderage,
    ReportReason.other => l10n.reportOther,
  };
}

class ReportPage extends StatefulWidget {
  const ReportPage({
    super.key,
    required this.userId,
    this.matchId,
    this.messageId,
  });

  final String userId;
  final String? matchId;
  final String? messageId;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  ReportReason _reason = ReportReason.spam;
  final _description = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final reason in ReportReason.values)
            RadioListTile<ReportReason>(
              title: Text(
                reportReasonLabel(l10n, reason),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: reason,
              groupValue: _reason,
              onChanged: (value) {
                if (value != null) {
                  setState(() => _reason = value);
                }
              },
            ),
          MevoraTextField(
            controller: _description,
            label: l10n.reportDescription,
            maxLines: 4,
          ),
          const SizedBox(height: 24),
          MevoraButton(
            label: l10n.submitReport,
            isLoading: _sending,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _sending = true);
    final l10n = AppLocalizations.of(context);
    try {
      await SocialScope.of(context).safetyRepository.reportUser(
        userId: widget.userId,
        reason: _reason.firestoreValue,
        matchId: widget.matchId,
        messageId: widget.messageId,
        description: _description.text,
      );
      await BoostScope.maybeOf(context)?.analytics?.logEvent(
        AnalyticsEvents.reportSubmitted,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.reportThanks)),
      );
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.somethingWentWrong)),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    final block = await MevoraDialog.show(
      context,
      title: l10n.offerBlockTitle,
      message: l10n.offerBlockMessage,
      confirmLabel: l10n.block,
    );
    if (block == true && mounted) {
      await SocialScope.of(context).safetyRepository.blockUser(
        userId: widget.userId,
        matchId: widget.matchId,
      );
      await BoostScope.maybeOf(context)?.analytics?.logEvent(
        AnalyticsEvents.userBlocked,
      );
    }
    if (mounted) {
      context.pop();
    }
  }
}
