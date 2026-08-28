import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_result.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_explanation.dart';
import 'package:mevora/l10n/app_localizations.dart';

/// Turns technical Why You Matched reasons into short, natural copy.
///
/// Rules: evidence-backed only; never invent; never use manipulative claims.
abstract final class WhyYouMatchedExplanationEngine {
  /// Soft caps so UI stays scannable (titles short, evidence one line).
  static const maxTitleLength = 72;
  static const maxBodyLength = 140;
  static const maxArgLength = 48;

  /// Phrases that must never appear in Why You Matched copy.
  static const forbiddenPhrases = [
    'ruh eşiniz',
    'mükemmel çiftsiniz',
    'kesinlikle birbiriniz için yaratılmışsınız',
    'bilimsel olarak uyumlusunuz',
    'soulmate',
    'perfect couple',
    'made for each other',
    'scientifically compatible',
  ];

  static String sectionTitle(AppLocalizations l10n) => l10n.whyYouMatch;

  /// Resolves one reason. Returns null when evidence is missing/invalid
  /// or localization keys/args cannot be resolved safely.
  static WhyYouMatchedExplanation? explain(
    AppLocalizations l10n,
    WhyYouMatchedReason reason,
  ) {
    if (!reason.evidence.isValid) {
      return null;
    }

    final title = _resolveTitle(l10n, reason.title);
    final body = _resolveBody(
      l10n,
      reason.description,
      reason.descriptionArgs,
    );
    if (title == null || body == null) {
      return null;
    }

    final clippedTitle = _clip(title, maxTitleLength);
    final clippedBody = _clip(body, maxBodyLength);
    final explanation = WhyYouMatchedExplanation(
      reasonId: reason.id,
      title: clippedTitle,
      body: clippedBody,
      categoryWire: reason.category.name,
    );

    if (containsForbiddenPhrase(explanation.combined)) {
      return null;
    }
    return explanation;
  }

  static List<WhyYouMatchedExplanation> explainAll(
    AppLocalizations l10n,
    Iterable<WhyYouMatchedReason> reasons,
  ) {
    final out = <WhyYouMatchedExplanation>[];
    for (final reason in reasons) {
      final explained = explain(l10n, reason);
      if (explained != null) {
        out.add(explained);
      }
    }
    return List.unmodifiable(out);
  }

  static List<WhyYouMatchedExplanation> explainResult(
    AppLocalizations l10n,
    WhyYouMatchedResult result,
  ) {
    if (!result.available) {
      return const [];
    }
    return explainAll(l10n, result.reasons);
  }

  static String insufficientDataMessage(AppLocalizations l10n) =>
      l10n.wymInsufficientData;

  static bool containsForbiddenPhrase(String text) {
    final lower = text.toLowerCase();
    for (final phrase in forbiddenPhrases) {
      if (lower.contains(phrase.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  static String? _resolveTitle(AppLocalizations l10n, String key) {
    return switch (key) {
      'wymHumorTitle' => l10n.wymHumorTitle,
      'wymMusicTitle' => l10n.wymMusicTitle,
      'wymInterestsTitle' => l10n.wymInterestsTitle,
      'wymLifestyleTitle' => l10n.wymLifestyleTitle,
      'wymPreferencesTitle' => l10n.wymPreferencesTitle,
      'wymCommunicationTitle' => l10n.wymCommunicationTitle,
      'wymDistanceNearbyTitle' => l10n.wymDistanceNearbyTitle,
      'wymDistanceTitle' => l10n.wymDistanceTitle,
      _ => null,
    };
  }

  static String? _resolveBody(
    AppLocalizations l10n,
    String key,
    List<String> args,
  ) {
    final a = args.map(_sanitizeArg).toList();
    return switch (key) {
      'wymHumorEvidence' =>
        a.length >= 2 ? l10n.wymHumorEvidence(a[0], a[1]) : null,
      'wymHumorDimsEvidence' =>
        a.length >= 2 ? l10n.wymHumorDimsEvidence(a[0], a[1]) : null,
      'wymHumorScoreEvidence' =>
        a.isNotEmpty ? l10n.wymHumorScoreEvidence(a[0]) : null,
      'wymMusicArtistsNamedEvidence' =>
        a.length >= 2 ? l10n.wymMusicArtistsNamedEvidence(a[0], a[1]) : null,
      'wymMusicArtistsCountEvidence' =>
        a.isNotEmpty ? l10n.wymMusicArtistsCountEvidence(a[0]) : null,
      'wymMusicTracksEvidence' =>
        a.isNotEmpty ? l10n.wymMusicTracksEvidence(a[0]) : null,
      'wymMusicGenresNamedEvidence' =>
        a.length >= 2 ? l10n.wymMusicGenresNamedEvidence(a[0], a[1]) : null,
      'wymMusicGenresCountEvidence' =>
        a.isNotEmpty ? l10n.wymMusicGenresCountEvidence(a[0]) : null,
      'wymMusicScoreEvidence' =>
        a.isNotEmpty ? l10n.wymMusicScoreEvidence(a[0]) : null,
      'wymInterestsEvidence' =>
        a.length >= 2 ? l10n.wymInterestsEvidence(a[0], a[1]) : null,
      'wymLifestyleEvidence' =>
        a.length >= 3 ? l10n.wymLifestyleEvidence(a[0], a[1], a[2]) : null,
      'wymPreferencesLanguageEvidence' =>
        a.isNotEmpty ? l10n.wymPreferencesLanguageEvidence(a[0]) : null,
      'wymCommunicationEvidence' => l10n.wymCommunicationEvidence,
      'wymDistanceNearbyEvidence' => l10n.wymDistanceNearbyEvidence,
      'wymDistanceKmEvidence' =>
        a.isNotEmpty ? l10n.wymDistanceKmEvidence(a[0]) : null,
      _ => null,
    };
  }

  static String _sanitizeArg(String raw) {
    final trimmed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return _clip(trimmed, maxArgLength);
  }

  static String _clip(String value, int max) {
    if (value.length <= max) {
      return value;
    }
    if (max <= 1) {
      return '…';
    }
    return '${value.substring(0, max - 1)}…';
  }
}
