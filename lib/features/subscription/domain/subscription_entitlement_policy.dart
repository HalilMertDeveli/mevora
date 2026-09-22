import 'package:mevora/features/subscription/domain/entities/subscription_lifecycle.dart';
import 'package:mevora/features/subscription/domain/repositories/subscription_repository.dart';

/// Client mirror of `functions/src/subscription/entitlementPolicy.ts`.
///
/// The server is authoritative — it writes the document and it gates every
/// premium backend call. This exists so the UI reaches the same answer from
/// the same data instead of trusting a stored boolean that may have aged out
/// between writes, and so a malformed document fails safe to free.
///
/// Keep the two implementations in step; the backend tests and
/// `test/features/subscription/` cover the same table of cases.
abstract final class SubscriptionEntitlementPolicy {
  /// Maps a raw `users/{uid}/subscription/current` document to effective
  /// entitlement. [data] may be null (no document) or partial (legacy write).
  static PremiumStatus evaluate(
    Map<String, dynamic>? data, {
    required DateTime now,
    DateTime? Function(Object? value)? dateParser,
  }) {
    if (data == null || data.isEmpty) {
      return PremiumStatus.free;
    }
    final DateTime? Function(Object?) parseDate = dateParser ?? _parseDate;

    final DateTime? expiresAt = parseDate(data['expiresAt']);
    final DateTime? graceUntil = parseDate(data['graceUntil']);
    final String? platform = _parseText(data['platform']);
    final String? productId = _parseText(data['productId']);
    final bool autoRenewing = data['autoRenewing'] == true;

    var lifecycle = SubscriptionLifecycle.fromWire(data['status']);
    var grantsPremium = data['entitlement'] == 'premium';

    if (lifecycle == SubscriptionLifecycle.none) {
      // Pre-P0 document: only `isPremium` and an optional `expiresAt`.
      final bool legacyPremium = data['isPremium'] == true;
      lifecycle = legacyPremium
          ? SubscriptionLifecycle.active
          : SubscriptionLifecycle.expired;
      grantsPremium = legacyPremium;
    }

    PremiumStatus lapsed(DateTime? accessUntil) => PremiumStatus(
      expiresAt: expiresAt,
      lifecycle: lifecycle,
      accessUntil: accessUntil,
      graceUntil: graceUntil,
      autoRenewing: autoRenewing,
      platform: platform,
      productId: productId,
    );

    PremiumStatus granted(DateTime? accessUntil) => PremiumStatus(
      isPremium: true,
      expiresAt: expiresAt,
      lifecycle: lifecycle,
      accessUntil: accessUntil,
      graceUntil: graceUntil,
      autoRenewing: autoRenewing,
      platform: platform,
      productId: productId,
    );

    switch (lifecycle) {
      case SubscriptionLifecycle.none:
      case SubscriptionLifecycle.revoked:
      case SubscriptionLifecycle.refunded:
      case SubscriptionLifecycle.expired:
      // Paused and pending deny access before any deadline is consulted: a
      // paused plan keeps a future expiry, and a pending one may carry a
      // legacy isPremium mirror. Neither may leak access through those.
      case SubscriptionLifecycle.paused:
      case SubscriptionLifecycle.pending:
        return lapsed(null);
      case SubscriptionLifecycle.cancelled:
        // Auto-renew off; honour the remaining paid period only.
        if (!grantsPremium || expiresAt == null) {
          return lapsed(expiresAt);
        }
        return expiresAt.isAfter(now) ? granted(expiresAt) : lapsed(expiresAt);
      case SubscriptionLifecycle.gracePeriod:
      case SubscriptionLifecycle.billingRetry:
        final DateTime? until = _latest(graceUntil, expiresAt);
        if (!grantsPremium || until == null) {
          return lapsed(until);
        }
        return until.isAfter(now) ? granted(until) : lapsed(until);
      case SubscriptionLifecycle.active:
        if (!grantsPremium) {
          return lapsed(null);
        }
        final DateTime? until = _latest(expiresAt, graceUntil);
        if (until == null) {
          // Manual / lifetime grants carry no expiry.
          return granted(null);
        }
        return until.isAfter(now) ? granted(until) : lapsed(until);
    }
  }

  static DateTime? _latest(DateTime? a, DateTime? b) {
    if (a == null) {
      return b;
    }
    if (b == null) {
      return a;
    }
    return a.isAfter(b) ? a : b;
  }

  static String? _parseText(Object? value) {
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is DateTime) {
      return value;
    }
    return null;
  }
}
