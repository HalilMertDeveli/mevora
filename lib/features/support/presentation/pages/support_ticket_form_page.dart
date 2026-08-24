import 'dart:async';
import 'dart:typed_data';

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mevora/core/config/auth_scope.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/di/support_scope.dart';
import 'package:mevora/features/support/domain/models/support_ticket.dart';
import 'package:mevora/features/support/domain/repositories/support_repository.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';
import 'package:mevora/shared/widgets/mevora_text_field.dart';

class SupportTicketFormPage extends StatefulWidget {
  const SupportTicketFormPage({super.key});

  @override
  State<SupportTicketFormPage> createState() => _SupportTicketFormPageState();
}

class _SupportTicketFormPageState extends State<SupportTicketFormPage> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  SupportTicketCategory _category = SupportTicketCategory.account;
  Uint8List? _attachment;
  String? _attachmentName;
  String? _attachmentType;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportCreateTicket)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        children: [
          DropdownButtonFormField<SupportTicketCategory>(
            value: _category,
            decoration: InputDecoration(labelText: l10n.supportTicketCategory),
            items: [
              for (final category in SupportTicketCategory.values)
                DropdownMenuItem(
                  value: category,
                  child: Text(_categoryLabel(l10n, category)),
                ),
            ],
            onChanged: _sending
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _category = value);
                    }
                  },
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            controller: _subject,
            label: l10n.supportTicketSubject,
            enabled: !_sending,
          ),
          const SizedBox(height: AppSpacing.md),
          MevoraTextField(
            controller: _message,
            label: l10n.supportTicketMessage,
            maxLines: 6,
            enabled: !_sending,
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _sending ? null : () => unawaited(_pickAttachment()),
            icon: const Icon(Icons.attach_file),
            label: Text(
              _attachment == null
                  ? l10n.supportTicketAddScreenshot
                  : l10n.supportTicketScreenshotAttached,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          MevoraButton(
            label: l10n.supportTicketSubmit,
            isLoading: _sending,
            onPressed: _sending ? null : () => unawaited(_submit()),
          ),
        ],
      ),
    );
  }

  String _categoryLabel(AppLocalizations l10n, SupportTicketCategory category) {
    return switch (category) {
      SupportTicketCategory.account => l10n.supportCategoryAccount,
      SupportTicketCategory.matches => l10n.supportCategoryMatches,
      SupportTicketCategory.messaging => l10n.supportCategoryMessaging,
      SupportTicketCategory.photos => l10n.supportCategoryPhotos,
      SupportTicketCategory.safety => l10n.supportCategorySafety,
      SupportTicketCategory.technical => l10n.supportCategoryTechnical,
      SupportTicketCategory.other => l10n.supportCategoryOther,
    };
  }

  Future<void> _pickAttachment() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null || !mounted) {
      return;
    }
    final bytes = await picked.readAsBytes();
    setState(() {
      _attachment = Uint8List.fromList(bytes);
      _attachmentName = picked.name;
      _attachmentType = picked.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final uid = AuthScope.of(context).user?.id;
    if (uid == null) {
      setState(() => _error = l10n.needSignIn);
      return;
    }
    if (_subject.text.trim().isEmpty || _message.text.trim().isEmpty) {
      setState(() => _error = l10n.supportTicketValidation);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final repository = SupportScope.of(context).repository;
      await repository.createTicket(
        userId: uid,
        draft: SupportTicketDraft(
          category: _category,
          subject: _subject.text.trim(),
          message: _message.text.trim(),
          attachmentBytes: _attachment,
          attachmentContentType: _attachmentType,
          attachmentFileName: _attachmentName,
        ),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.supportTicketSubmitted)),
      );
      context.pop();
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _sending = false;
        _error = l10n.supportTicketFailed;
      });
    }
  }
}
