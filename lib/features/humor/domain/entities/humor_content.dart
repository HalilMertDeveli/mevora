import 'package:mevora/features/humor/domain/entities/humor_calibration.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';

enum HumorContentType { image, video, text, meme }

/// Feed-safe humor item (no internal vectors / safety flags).
class HumorContent {
  const HumorContent({
    required this.contentId,
    required this.type,
    required this.language,
    required this.category,
    this.humorTags = const [],
    this.textBody,
    this.downloadUrl,
    this.thumbUrl,
    this.durationMs,
    this.aspectRatio,
    this.calibrationStage,
    this.attribution,
  });

  final String contentId;
  final HumorContentType type;
  final String language;
  final HumorCategory category;
  final List<String> humorTags;
  final String? textBody;
  final String? downloadUrl;
  final String? thumbUrl;
  final int? durationMs;
  final double? aspectRatio;

  /// Set only while initial calibration is running. `null` for ordinary feed
  /// content. The server never sends the anchor slot behind it.
  final HumorCalibrationStage? calibrationStage;

  /// Who made a third-party item (GIPHY and similar providers require the
  /// credit to be shown). `null` for curated Mevora content.
  final HumorContentAttribution? attribution;

  bool get isCalibrationItem => calibrationStage != null;

  HumorContent copyWithCalibrationStage(HumorCalibrationStage? stage) {
    return HumorContent(
      contentId: contentId,
      type: type,
      language: language,
      category: category,
      humorTags: humorTags,
      textBody: textBody,
      downloadUrl: downloadUrl,
      thumbUrl: thumbUrl,
      durationMs: durationMs,
      aspectRatio: aspectRatio,
      calibrationStage: stage,
      attribution: attribution,
    );
  }

  bool get hasText => textBody != null && textBody!.trim().isNotEmpty;
  bool get hasMedia =>
      (downloadUrl != null && downloadUrl!.isNotEmpty) ||
      (thumbUrl != null && thumbUrl!.isNotEmpty);

  static HumorContentType parseType(String? raw) {
    switch (raw) {
      case 'image':
        return HumorContentType.image;
      case 'video':
        return HumorContentType.video;
      case 'meme':
        return HumorContentType.meme;
      case 'text':
      default:
        return HumorContentType.text;
    }
  }
}

/// Credit for a provider-sourced item, as the feed sends it. Only [provider]
/// is required; everything else is optional and shown only when present.
class HumorContentAttribution {
  const HumorContentAttribution({
    required this.provider,
    this.displayName,
    this.username,
    this.sourceUrl,
    this.verified = false,
  });

  /// Provider key, e.g. `giphy`.
  final String provider;
  final String? displayName;
  final String? username;
  final String? sourceUrl;
  final bool verified;

  /// Brand spelling for known providers; anything else as sent.
  String get providerLabel {
    switch (provider.toLowerCase()) {
      case 'giphy':
        return 'GIPHY';
      case 'tenor':
        return 'Tenor';
      default:
        return provider;
    }
  }

  /// The creator's handle, or else their display name, if either is known.
  String? get creatorLabel {
    final handle = username;
    if (handle != null && handle.isNotEmpty) {
      return handle.startsWith('@') ? handle : '@$handle';
    }
    final name = displayName;
    return name != null && name.isNotEmpty ? name : null;
  }

  /// e.g. `GIPHY · @username`, or just `GIPHY` without a known creator.
  String get label {
    final creator = creatorLabel;
    return creator == null ? providerLabel : '$providerLabel · $creator';
  }

  /// Unknown or malformed data yields `null` (no label) rather than throwing:
  /// an older or newer backend must never break the feed.
  static HumorContentAttribution? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final provider = _text(raw['provider']);
    if (provider == null) {
      return null;
    }
    final source = _text(raw['sourceUrl']);
    final sourceUri = source == null ? null : Uri.tryParse(source);
    final sourceOk =
        sourceUri != null &&
        (sourceUri.scheme == 'https' || sourceUri.scheme == 'http');
    return HumorContentAttribution(
      provider: provider,
      displayName: _text(raw['displayName']),
      username: _text(raw['username']),
      sourceUrl: sourceOk ? source : null,
      verified: raw['verified'] == true,
    );
  }

  static String? _text(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class HumorFeedPage {
  const HumorFeedPage({
    required this.items,
    this.nextCursor,
    this.profileBuilding = true,
    this.interactionCount = 0,
    this.calibration = HumorCalibration.empty,
    this.catalogExhausted = false,
    this.catalogEmpty = false,
  });

  final List<HumorContent> items;
  final String? nextCursor;
  final bool profileBuilding;
  final int interactionCount;

  /// Server-owned initial calibration progress. Never inferred on the client.
  final HumorCalibration calibration;

  /// The user has worked through everything currently in the catalog — a
  /// normal, explainable end state rather than an error.
  final bool catalogExhausted;

  /// No servable content exists at all. An operational problem, not progress,
  /// and worth distinguishing so the empty state does not blame the user.
  final bool catalogEmpty;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
