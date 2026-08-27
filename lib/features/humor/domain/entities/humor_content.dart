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
    this.embedUrl,
    this.durationMs,
    this.aspectRatio,
    this.provider,
    this.attributionRequired = false,
    this.sourceUrl,
  });

  final String contentId;
  final HumorContentType type;
  final String language;
  final HumorCategory category;
  final List<String> humorTags;
  final String? textBody;
  final String? downloadUrl;
  final String? thumbUrl;
  final String? embedUrl;
  final int? durationMs;
  final double? aspectRatio;
  final String? provider;
  final bool attributionRequired;
  final String? sourceUrl;

  bool get hasText => textBody != null && textBody!.trim().isNotEmpty;
  bool get hasMedia =>
      (downloadUrl != null && downloadUrl!.isNotEmpty) ||
      (thumbUrl != null && thumbUrl!.isNotEmpty) ||
      (embedUrl != null && embedUrl!.isNotEmpty);

  bool get isYoutube {
    final providerName = provider?.toLowerCase() ?? '';
    if (providerName == 'youtube') {
      return true;
    }
    final embed = embedUrl ?? downloadUrl ?? '';
    return embed.contains('youtube.com/embed') ||
        embed.contains('youtu.be/') ||
        embed.contains('youtube.com/watch');
  }

  String? get youtubeVideoId {
    final raw = embedUrl ?? downloadUrl ?? sourceUrl ?? '';
    final embedMatch = RegExp(r'youtube\.com/embed/([^?&/]+)').firstMatch(raw);
    if (embedMatch != null) {
      return embedMatch.group(1);
    }
    final watchMatch = RegExp(r'[?&]v=([^&]+)').firstMatch(raw);
    if (watchMatch != null) {
      return watchMatch.group(1);
    }
    final shortMatch = RegExp(r'youtu\.be/([^?&/]+)').firstMatch(raw);
    return shortMatch?.group(1);
  }

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
    this.isPremium,
    this.adsEnabled,
  });

  final List<HumorContent> items;
  final String? nextCursor;
  final bool profileBuilding;
  final int interactionCount;

  /// Server-authoritative premium hint from `getHumorFeed` (optional on mock).
  final bool? isPremium;
  final bool? adsEnabled;

  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;
}
