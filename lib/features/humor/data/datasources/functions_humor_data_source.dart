import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/humor/data/datasources/humor_data_source.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/humor/domain/entities/humor_compatibility.dart';
import 'package:mevora/features/humor/domain/entities/humor_content.dart';
import 'package:mevora/features/humor/domain/entities/humor_rating.dart';
import 'package:mevora/features/humor/domain/entities/user_humor_profile.dart';
import 'package:mevora/features/humor/domain/services/humor_feed_policy.dart';

/// Cloud Functions surface for Humor Lab.
class FunctionsHumorDataSource implements HumorDataSource {
  FunctionsHumorDataSource({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<HumorFeedPage> getFeed({
    List<String>? languages,
    int? limit,
    String? cursor,
  }) async {
    final data = await _backend.invoke('getHumorFeed', {
      if (languages != null) 'languages': languages,
      'limit': limit ?? HumorFeedPolicy.pageSize,
      if (cursor != null) 'cursor': cursor,
    });
    return HumorFeedPage(
      items: _parseItems(data['items']),
      nextCursor: data['nextCursor'] as String?,
      profileBuilding: data['profileBuilding'] == true,
      interactionCount: firestoreInt(data['interactionCount'], 0),
    );
  }

  @override
  Future<HumorFeedbackResult> submitFeedback({
    required String contentId,
    required HumorRating rating,
    int dwellMs = 0,
    int replayCount = 0,
    bool skipped = false,
    bool saved = false,
    bool? swipeUp,
    bool? swipeDown,
  }) async {
    final gestureHints = <String, bool>{};
    if (swipeUp == true) {
      gestureHints['swipeUp'] = true;
    }
    if (swipeDown == true) {
      gestureHints['swipeDown'] = true;
    }
    final data = await _backend.invoke('submitHumorFeedback', {
      'contentId': contentId,
      'rating': rating.apiValue,
      'dwellMs': dwellMs,
      'replayCount': replayCount,
      'skipped': skipped,
      'saved': saved,
      if (gestureHints.isNotEmpty) 'gestureHints': gestureHints,
    });
    return HumorFeedbackResult(
      ok: data['ok'] == true,
      profileBuilding: data['profileBuilding'] == true,
      interactionCount: firestoreInt(data['interactionCount'], 0),
      confidence: _asDouble(data['confidence']),
    );
  }

  @override
  Future<UserHumorProfile> getProfile({bool detailed = false}) async {
    final data = await _backend.invoke('getHumorProfile', {
      'detailed': detailed,
    });
    return _parseProfile(data);
  }

  @override
  Future<HumorCompatibility> getMatchCompatibility(String matchId) async {
    final data = await _backend.invoke('getMatchHumorCompatibility', {
      'matchId': matchId,
    });
    if (data['available'] != true) {
      return HumorCompatibility(
        available: false,
        reason: data['reason'] as String?,
        confidence: _asDouble(data['confidence']),
      );
    }
    final scoreRaw = data['score'];
    final score = scoreRaw == null ? null : firestoreInt(scoreRaw, 0);
    return HumorCompatibility(
      available: true,
      score: score,
      strongestShared: _parseCategories(data['strongestShared']),
      differences: _parseDifferences(data['differences']),
      confidence: _asDouble(data['confidence']),
      reason: data['reason'] as String?,
    );
  }

  @override
  Future<void> reportContent({
    required String contentId,
    String reason = 'other',
    String details = '',
  }) async {
    await _backend.invoke('reportHumorContent', {
      'contentId': contentId,
      'reason': reason,
      'details': details,
    });
  }

  List<HumorContent> _parseItems(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final items = <HumorContent>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final id = map['contentId'] as String?;
      if (id == null || id.isEmpty) {
        continue;
      }
      final media = map['media'] is Map
          ? Map<String, dynamic>.from(map['media'] as Map)
          : const <String, dynamic>{};
      items.add(
        HumorContent(
          contentId: id,
          type: HumorContent.parseType(map['type'] as String?),
          language: (map['language'] as String?) ?? 'en',
          category: HumorCategory.parse((map['category'] as String?) ?? 'meme'),
          humorTags: firestoreStringList(map['humorTags']),
          textBody: media['textBody'] as String?,
          downloadUrl: media['downloadUrl'] as String?,
          thumbUrl: media['thumbUrl'] as String?,
          durationMs: media['durationMs'] == null
              ? null
              : firestoreInt(media['durationMs'], 0),
          aspectRatio: media['aspectRatio'] == null
              ? null
              : _asDouble(media['aspectRatio']),
        ),
      );
    }
    return items;
  }

  UserHumorProfile _parseProfile(Map<String, dynamic> data) {
    final topRaw = data['topVibes'];
    final top = <HumorVibe>[];
    if (topRaw is List) {
      for (final item in topRaw) {
        if (item is! Map) {
          continue;
        }
        final map = Map<String, dynamic>.from(item);
        final dim = HumorCategory.tryParse(map['dim'] as String?);
        if (dim == null) {
          continue;
        }
        top.add(HumorVibe(category: dim, value: firestoreInt(map['value'], 0)));
      }
    }
    final vector = <HumorCategory, double>{};
    final vectorRaw = data['vector'];
    if (vectorRaw is Map) {
      vectorRaw.forEach((key, value) {
        if (key is! String) {
          return;
        }
        final dim = HumorCategory.tryParse(key);
        if (dim == null) {
          return;
        }
        vector[dim] = _asDouble(value);
      });
    }
    final interactionCount = firestoreInt(data['interactionCount'], 0);
    return UserHumorProfile(
      confidence: _asDouble(data['confidence']),
      interactionCount: interactionCount,
      profileBuilding:
          data['profileBuilding'] == true ||
          HumorFeedPolicy.isBuilding(interactionCount),
      topVibes: top,
      vector: vector,
      exploredCategories: firestoreStringList(data['exploredCategories']),
      version: firestoreInt(data['version'], 1),
    );
  }

  List<HumorCategory> _parseCategories(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final out = <HumorCategory>[];
    for (final item in raw) {
      final parsed = HumorCategory.tryParse(item?.toString());
      if (parsed != null) {
        out.add(parsed);
      }
    }
    return out;
  }

  List<HumorDifference> _parseDifferences(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final out = <HumorDifference>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final dim = HumorCategory.tryParse(map['dim'] as String?);
      if (dim == null) {
        continue;
      }
      out.add(
        HumorDifference(
          dim: dim,
          a: _asDouble(map['a']),
          b: _asDouble(map['b']),
        ),
      );
    }
    return out;
  }

  double _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}
