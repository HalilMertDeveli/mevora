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
  });

  final List<HumorContent> items;
  final String? nextCursor;
  final bool profileBuilding;
  final int interactionCount;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
