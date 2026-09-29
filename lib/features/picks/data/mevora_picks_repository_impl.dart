import 'package:mevora/core/data/firestore_codec.dart';
import 'package:mevora/core/errors/failure_mapper.dart';
import 'package:mevora/core/errors/result.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/discovery/data/parsers/discovery_candidate_parser.dart';
import 'package:mevora/features/discovery/domain/repositories/discovery_repository.dart';
import 'package:mevora/features/humor/domain/entities/humor_category.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/domain/repositories/mevora_picks_repository.dart';

/// Calls `getMevoraPicks` and the shared `recordDiscoveryDecision` callable.
class MevoraPicksRepositoryImpl implements MevoraPicksRepository {
  MevoraPicksRepositoryImpl({required BackendCallable backend})
    : _backend = backend;

  final BackendCallable _backend;

  @override
  Future<Result<MevoraPicksBatch>> loadPicks() async {
    try {
      final data = await _backend.invoke('getMevoraPicks', const {});
      return Success(MevoraPicksParser.parseBatch(data));
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }

  @override
  Future<Result<DiscoveryDecisionResult>> decide({
    required MevoraPick pick,
    required DiscoveryDecision decision,
  }) async {
    try {
      final data = await _backend.invoke('recordDiscoveryDecision', {
        'candidateUid': pick.uid,
        'action': decision.name,
      });
      return Success(
        DiscoveryDecisionResult(
          matched: data['matched'] == true,
          matchId: data['matchId'] as String?,
        ),
      );
    } on Object catch (error) {
      return Err(FailureMapper.from(error));
    }
  }
}

/// Parses the `getMevoraPicks` response. Unknown or malformed entries are
/// dropped rather than rendered with guessed data.
abstract final class MevoraPicksParser {
  static MevoraPicksBatch parseBatch(Map<String, dynamic> data) {
    final generationId = data['generationId'] as String?;
    final picks = <MevoraPick>[];
    final rawPicks = data['picks'];
    if (rawPicks is List) {
      for (final item in rawPicks) {
        if (item is! Map) {
          continue;
        }
        final pick = parsePick(Map<String, dynamic>.from(item), generationId);
        if (pick != null) {
          picks.add(pick);
        }
      }
    }
    picks.sort((a, b) => a.rank.compareTo(b.rank));
    final refreshAtMs = data['refreshAtMs'];
    return MevoraPicksBatch(
      status: _status(data['status'], picks),
      emptyReason: _emptyReason(data['emptyReason']),
      generationId: generationId,
      refreshAt: refreshAtMs is num
          ? DateTime.fromMillisecondsSinceEpoch(refreshAtMs.toInt())
          : null,
      targetCount: firestoreInt(data['targetCount'], 6),
      picks: picks,
    );
  }

  static MevoraPick? parsePick(Map<String, dynamic> raw, String? batchId) {
    final meta = raw['pick'];
    if (meta is! Map) {
      return null;
    }
    final pickMeta = Map<String, dynamic>.from(meta);
    final pickType = PickType.tryParse(pickMeta['pickType']);
    final candidate = DiscoveryCandidateParser.parse(raw);
    if (pickType == null || candidate == null) {
      return null;
    }
    final labels = <PickType>[];
    final rawLabels = pickMeta['labels'];
    if (rawLabels is List) {
      for (final label in rawLabels) {
        final parsed = PickType.tryParse(label);
        if (parsed != null) {
          labels.add(parsed);
        }
      }
    }
    if (!labels.contains(pickType)) {
      labels.insert(0, pickType);
    }
    final traits = <HumorCategory>[];
    final rawTraits = pickMeta['sharedHumorTraits'];
    if (rawTraits is List) {
      for (final trait in rawTraits) {
        final parsed = HumorCategory.tryParse(trait as String?);
        if (parsed != null) {
          traits.add(parsed);
        }
      }
    }
    final humor = pickMeta['humorCompatibilityScore'];
    return MevoraPick(
      candidate: candidate,
      pickId: (pickMeta['pickId'] as String?) ?? '',
      generationId: (pickMeta['generationId'] as String?) ?? batchId ?? '',
      pickType: pickType,
      labels: labels,
      reasons: _reasons(pickMeta['reasons']),
      rank: firestoreInt(pickMeta['rank'], 0),
      overallScore: firestoreInt(pickMeta['overallScore'], 0),
      humorScore: humor is num ? humor.round() : null,
      sharedHumorTraits: traits,
    );
  }

  static List<PickReason> _reasons(Object? raw) {
    if (raw is! List) {
      return const [];
    }
    final out = <PickReason>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final type = PickReasonType.tryParse(item['type']);
      if (type == null) {
        continue;
      }
      final score = item['score'];
      final meta = <String, Object>{};
      final rawMeta = item['meta'];
      if (rawMeta is Map) {
        rawMeta.forEach((key, value) {
          if (key is! String || value == null) {
            return;
          }
          if (value is num) {
            meta[key] = value;
          } else if (value is String) {
            meta[key] = value;
          } else if (value is List) {
            meta[key] = value.whereType<String>().toList();
          }
        });
      }
      out.add(
        PickReason(
          type: type,
          score: score is num ? score.round() : null,
          strength: item['strength'] == 'strong'
              ? PickReasonStrength.strong
              : PickReasonStrength.notable,
          meta: meta,
        ),
      );
    }
    return out;
  }

  static PicksStatus _status(Object? raw, List<MevoraPick> picks) {
    if (picks.isEmpty) {
      return PicksStatus.empty;
    }
    return raw == 'lowSupply' ? PicksStatus.lowSupply : PicksStatus.ready;
  }

  static PicksEmptyReason? _emptyReason(Object? raw) {
    return switch (raw) {
      'allDecided' => PicksEmptyReason.allDecided,
      'noCandidates' => PicksEmptyReason.noCandidates,
      'discoveryDisabled' => PicksEmptyReason.discoveryDisabled,
      _ => null,
    };
  }
}
