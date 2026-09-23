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
