import 'package:mevora/features/humor/domain/entities/humor_category.dart';

enum HumorContentType { image, video, text, meme }

/// YouTube video ids are 11 chars from a restricted alphabet.
final RegExp _youtubeVideoIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

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
    this.sourceId,
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

  /// Provider-native id (e.g. YouTube videoId / Giphy gif id).
  final String? sourceId;
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
    final embed = embedUrl ?? '';
    if (embed.contains('youtube.com/embed') ||
        embed.contains('youtu.be/') ||
        embed.contains('youtube.com/watch')) {
      return true;
    }
    // Never classify a YouTube watch/embed string sitting in downloadUrl as
    // "direct video" — that path must stay iframe-only.
    final download = downloadUrl ?? '';
    return download.contains('youtube.com/embed') ||
        download.contains('youtu.be/') ||
        download.contains('youtube.com/watch');
  }

  bool get isGiphy {
    final providerName = provider?.toLowerCase() ?? '';
    if (providerName == 'giphy') {
      return true;
    }
    final blob = '${downloadUrl ?? ''} ${thumbUrl ?? ''} ${sourceUrl ?? ''}';
    return blob.contains('giphy.com');
  }

  String? get youtubeVideoId {
    final fromSource = _validatedYoutubeId(sourceId);
    if (fromSource != null) {
      return fromSource;
    }

    for (final raw in [embedUrl, sourceUrl, downloadUrl]) {
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final embedMatch = RegExp(
        r'youtube\.com/embed/([^?&/#]+)',
      ).firstMatch(raw);
      final fromEmbed = _validatedYoutubeId(embedMatch?.group(1));
      if (fromEmbed != null) {
        return fromEmbed;
      }
      final watchMatch = RegExp(r'[?&]v=([^&/#]+)').firstMatch(raw);
      final fromWatch = _validatedYoutubeId(watchMatch?.group(1));
      if (fromWatch != null) {
        return fromWatch;
      }
      final shortMatch = RegExp(r'youtu\.be/([^?&/#]+)').firstMatch(raw);
      final fromShort = _validatedYoutubeId(shortMatch?.group(1));
      if (fromShort != null) {
        return fromShort;
      }
    }

    // Last resort: contentId shaped as ext_youtube_<id>
    const prefix = 'ext_youtube_';
    if (contentId.startsWith(prefix)) {
      return _validatedYoutubeId(contentId.substring(prefix.length));
    }
    return null;
  }

  static String? _validatedYoutubeId(String? raw) {
    final id = raw?.trim();
    if (id == null || id.isEmpty) {
      return null;
    }
    if (!_youtubeVideoIdPattern.hasMatch(id)) {
      return null;
    }
    return id;
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
