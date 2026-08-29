import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/compatibility/domain/entities/compatibility_snapshot.dart';
import 'package:mevora/features/matching/domain/models/incoming_likes.dart';

class FunctionsIncomingLikesRepository implements IncomingLikesRepository {
  FunctionsIncomingLikesRepository({required BackendCallable callable})
    : _callable = callable;

  final BackendCallable _callable;

  @override
  Future<IncomingLikesSnapshot> fetchIncomingLikes() async {
    final raw = await _callable.invoke('getIncomingLikes');
    final locked = raw['locked'] == true;
    final isPremium = raw['isPremium'] == true;
    final count = firestoreInt(
      raw['incomingLikeCount'] ?? raw['count'],
      0,
    );
    final itemsRaw = raw['items'];
    final items = <IncomingLikerPreview>[];
    if (!locked && itemsRaw is List) {
      for (final entry in itemsRaw) {
        if (entry is! Map) {
          continue;
        }
        final map = entry.map((k, v) => MapEntry(k.toString(), v));
        final uid = map['uid']?.toString() ?? '';
        if (uid.isEmpty) {
          continue;
        }
        final createdMs = map['createdAtMs'];
        items.add(
          IncomingLikerPreview(
            uid: uid,
            displayName: map['displayName']?.toString() ?? '',
            age: map['age'] == null ? null : firestoreInt(map['age'], 0),
            photoUrl: map['photoUrl']?.toString(),
            city: map['city']?.toString(),
            action: map['action']?.toString() ?? 'like',
            createdAt: createdMs is num
                ? DateTime.fromMillisecondsSinceEpoch(createdMs.toInt())
                : null,
            compatibility: CompatibilitySnapshot.fromMap({
              'compatibilityScore': map['compatibilityScore'],
              'compatibilityBreakdown': map['compatibilityBreakdown'],
              'sharedInterests': map['sharedInterests'],
              'compatibilityReasons': map['compatibilityReasons'],
            }),
          ),
        );
      }
    }
    return IncomingLikesSnapshot(
      locked: locked || !isPremium,
      isPremium: isPremium,
      premiumRequired: raw['premiumRequired'] == true || locked || !isPremium,
      count: count,
      items: locked || !isPremium ? const [] : items,
    );
  }
}
