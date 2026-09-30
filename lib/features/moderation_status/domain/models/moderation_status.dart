import 'package:mevora/core/identity/account_status.dart';

/// A decision Mevora's Trust & Safety team made about the member, as
/// returned by the `getMyModerationStatus` callable. It carries only what
/// the member may see: the type, a reason code, the member-facing message
/// and the appeal state. Who decided and internal notes never reach the app.
enum ModerationDecisionType {
  warning,
  temporarySuspension,
  permanentBan,
  photoRejected,
  photoRemoved,
  requireReverification,
  unknown;

  static ModerationDecisionType fromWire(Object? value) {
    return switch (value) {
      'WARNING' => ModerationDecisionType.warning,
      'TEMPORARY_SUSPENSION' => ModerationDecisionType.temporarySuspension,
      'PERMANENT_BAN' => ModerationDecisionType.permanentBan,
      'PHOTO_REJECTED' => ModerationDecisionType.photoRejected,
      'PHOTO_REMOVED' => ModerationDecisionType.photoRemoved,
      'REQUIRE_REVERIFICATION' => ModerationDecisionType.requireReverification,
      _ => ModerationDecisionType.unknown,
    };
  }
}

enum ModerationAppealStatus {
  open,
  inReview,
  resolved;

  static ModerationAppealStatus fromWire(Object? value) {
    return switch (value) {
      'in_review' => ModerationAppealStatus.inReview,
      'resolved' => ModerationAppealStatus.resolved,
      _ => ModerationAppealStatus.open,
    };
  }
}

enum ModerationAppealDecision {
  accepted,
  rejected;

  static ModerationAppealDecision? fromWire(Object? value) {
    return switch (value) {
      'accepted' || 'accept' => ModerationAppealDecision.accepted,
      'rejected' || 'reject' => ModerationAppealDecision.rejected,
      _ => null,
    };
  }
}

class ModerationAppeal {
  const ModerationAppeal({
    required this.appealId,
    required this.status,
    this.decision,
    this.message,
  });

  final String appealId;
  final ModerationAppealStatus status;
  final ModerationAppealDecision? decision;

  /// The reviewer's member-facing explanation, once resolved.
  final String? message;

  factory ModerationAppeal.fromMap(Map<String, dynamic> map) {
    return ModerationAppeal(
      appealId: _string(map['appealId']) ?? '',
      status: ModerationAppealStatus.fromWire(map['status']),
      decision: ModerationAppealDecision.fromWire(map['decision']),
      message: _string(map['message']),
    );
  }
}

class ModerationDecision {
  const ModerationDecision({
    required this.actionId,
    required this.type,
    this.reasonCode,
    this.message,
    this.effectiveAt,
    this.expiresAt,
    this.overturned = false,
    this.appealable = false,
    this.appeal,
  });

  final String actionId;
  final ModerationDecisionType type;
  final String? reasonCode;

  /// The member-facing message staff wrote for this decision, if any.
  final String? message;
  final DateTime? effectiveAt;
  final DateTime? expiresAt;

  /// Reversed later (for example by an accepted appeal).
  final bool overturned;

  /// An appeal can be filed now: none yet, not overturned, window open.
  final bool appealable;
  final ModerationAppeal? appeal;

  factory ModerationDecision.fromMap(Map<String, dynamic> map) {
    final appeal = map['appeal'];
    return ModerationDecision(
      actionId: _string(map['actionId']) ?? '',
      type: ModerationDecisionType.fromWire(map['type']),
      reasonCode: _string(map['reasonCode']),
      message: _string(map['message']),
      effectiveAt: _date(map['effectiveAt']),
      expiresAt: _date(map['expiresAt']),
      overturned: map['overturned'] == true,
      appealable: map['appealable'] == true,
      appeal: appeal is Map
          ? ModerationAppeal.fromMap(Map<String, dynamic>.from(appeal))
          : null,
    );
  }
}

class ModerationStatus {
  const ModerationStatus({
    required this.accountStatus,
    this.suspendedUntil,
    this.statusReasonCode,
    this.decisions = const [],
  });

  final AccountStatus accountStatus;
  final DateTime? suspendedUntil;
  final String? statusReasonCode;
  final List<ModerationDecision> decisions;

  factory ModerationStatus.fromMap(Map<String, dynamic> map) {
    final raw = map['decisions'];
    return ModerationStatus(
      accountStatus: AccountStatusX.fromFirestore(map['accountStatus']),
      suspendedUntil: _date(map['suspendedUntil']),
      statusReasonCode: _string(map['statusReasonCode']),
      decisions: raw is List
          ? [
              for (final item in raw)
                if (item is Map)
                  ModerationDecision.fromMap(Map<String, dynamic>.from(item)),
            ].where((d) => d.actionId.isNotEmpty).toList(growable: false)
          : const [],
    );
  }
}

/// What happened to an appeal the member submitted.
enum AppealSubmitOutcome {
  /// Filed now.
  created,

  /// This decision already has an appeal (idempotent per decision).
  alreadySubmitted,

  /// The 30-day window for this decision has passed.
  windowClosed,

  /// The decision cannot be appealed (type, already overturned, not theirs).
  notAllowed,

  /// The reason was rejected by the server (length).
  invalidReason,

  /// Network or server trouble; nothing is known to have been filed.
  failed,
}

/// Appeal reason bounds, mirrored from submitModerationAppeal.
abstract final class AppealReasonRules {
  static const int minLength = 10;
  static const int maxLength = 2000;

  static bool isValid(String reason) {
    final length = reason.trim().length;
    return length >= minLength && length <= maxLength;
  }
}

String? _string(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

DateTime? _date(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  return null;
}
