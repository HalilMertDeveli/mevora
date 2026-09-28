import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/core/di/boost_scope.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_chip.dart';

/// Opening line for an empty chat, built from the humor style both people
/// share. Tapping hands the text to [onUsed] — the chat pre-fills its
/// composer with it; nothing is ever sent from here.
///
/// The text is a fixed, localised template per category: deterministic,
/// testable, no model call at runtime.
class HumorChatStarterChip extends StatefulWidget {
  const HumorChatStarterChip({
    super.key,
    required this.sharedCategories,
    this.analytics,
    this.onUsed,
  });

  /// Shared humor styles, strongest first. The first one picks the template.
  final List<HumorCategory> sharedCategories;

  /// Overrides the analytics found in [BoostScope] (tests).
  final AnalyticsProvider? analytics;
  final ValueChanged<String>? onUsed;

  /// Starter text for [category]; the generic line when there is none.
  static String starterText(AppLocalizations l10n, HumorCategory? category) {
    return switch (category) {
      HumorCategory.sarcasm => l10n.humorChatStarterSarcasm,
      HumorCategory.absurd => l10n.humorChatStarterAbsurd,
      HumorCategory.silly => l10n.humorChatStarterSilly,
      HumorCategory.romantic => l10n.humorChatStarterRomantic,
      HumorCategory.dark => l10n.humorChatStarterDark,
      HumorCategory.meme => l10n.humorChatStarterMeme,
      HumorCategory.dry => l10n.humorChatStarterDry,
      HumorCategory.wordplay => l10n.humorChatStarterWordplay,
      HumorCategory.situational => l10n.humorChatStarterSituational,
      HumorCategory.cringe => l10n.humorChatStarterCringe,
      HumorCategory.teasing => l10n.humorChatStarterTeasing,
      null => l10n.humorChatStarter,
    };
  }

  @override
  State<HumorChatStarterChip> createState() => _HumorChatStarterChipState();
}

class _HumorChatStarterChipState extends State<HumorChatStarterChip> {
  var _shownLogged = false;

  HumorCategory? get _category =>
      widget.sharedCategories.isEmpty ? null : widget.sharedCategories.first;

  AnalyticsProvider? _analytics(BuildContext context) =>
      widget.analytics ?? BoostScope.maybeOf(context)?.analytics;

  Map<String, Object> get _params => {
    'category': _category?.apiValue ?? 'generic',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shownLogged) {
      return;
    }
    _shownLogged = true;
    final analytics = _analytics(context);
    if (analytics != null) {
      unawaited(
        analytics.logEvent(
          AnalyticsEvents.humorChatStarterShown,
          parameters: _params,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = HumorChatStarterChip.starterText(l10n, _category);
    return MevoraChip(
      label: text,
      avatar: const Icon(Icons.edit_note_rounded),
      wrapLabel: true,
      onSelected: (_) {
        final analytics = _analytics(context);
        if (analytics != null) {
          unawaited(
            analytics.logEvent(
              AnalyticsEvents.humorChatStarterUsed,
              parameters: _params,
            ),
          );
        }
        widget.onUsed?.call(text);
      },
    );
  }
}
