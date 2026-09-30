import 'package:flutter/foundation.dart';
import 'package:mevora/features/app_operations/domain/semantic_version.dart';

/// The store platforms the operations document can target separately.
/// Anything else (web, desktop, tests) is never version-gated.
enum AppPlatform { android, ios, other }

/// Features the owner can switch off at runtime. A feature is on unless the
/// document says `false` for it explicitly.
enum AppFeature {
  boost('boost'),
  calls('calls'),
  spotify('spotify'),
  humorLab('humorLab'),
  picks('picks');

  const AppFeature(this.key);

  /// The field name under `features` in the operations document.
  final String key;
}

enum AnnouncementSeverity { info, warning }

/// What the installed build is allowed to do, given the published minimums.
enum VersionGate { ok, updateRecommended, updateRequired }

/// One value per store platform.
@immutable
class PlatformValues {
  const PlatformValues({this.android, this.ios});

  final String? android;
  final String? ios;

  String? forPlatform(AppPlatform platform) => switch (platform) {
    AppPlatform.android => android,
    AppPlatform.ios => ios,
    AppPlatform.other => null,
  };

  Map<String, Object?> toJson() => {'android': android, 'ios': ios};

  @override
  bool operator ==(Object other) =>
      other is PlatformValues && other.android == android && other.ios == ios;

  @override
  int get hashCode => Object.hash(android, ios);
}

/// A plain-text notice the owner publishes to everyone. Never markup: it is
/// rendered as a single [Text], whatever characters it contains.
@immutable
class AppAnnouncement {
  const AppAnnouncement({
    required this.id,
    required this.message,
    this.enabled = true,
    this.title = '',
    this.severity = AnnouncementSeverity.info,
    this.startsAt,
    this.expiresAt,
  });

  final bool enabled;
  final String id;
  final String title;
  final String message;
  final AnnouncementSeverity severity;
  final DateTime? startsAt;
  final DateTime? expiresAt;

  /// Shown only while enabled and inside `[startsAt, expiresAt)`; a missing
  /// bound leaves that side open. Without an id or a message there is
  /// nothing to show and nothing to remember a dismissal by.
  bool isActiveAt(DateTime now) {
    if (!enabled || id.isEmpty || message.isEmpty) {
      return false;
    }
    final start = startsAt;
    if (start != null && now.isBefore(start)) {
      return false;
    }
    final end = expiresAt;
    if (end != null && !now.isBefore(end)) {
      return false;
    }
    return true;
  }

  /// The next moment [isActiveAt] can change after [now], if any.
  DateTime? nextBoundaryAfter(DateTime now) {
    final candidates = [
      startsAt,
      expiresAt,
    ].whereType<DateTime>().where((t) => t.isAfter(now)).toList()..sort();
    return candidates.isEmpty ? null : candidates.first;
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'id': id,
    'title': title,
    'message': message,
    'severity': severity.name,
    'startsAt': startsAt?.millisecondsSinceEpoch,
    'expiresAt': expiresAt?.millisecondsSinceEpoch,
  };

  static AppAnnouncement? fromMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    return AppAnnouncement(
      enabled: raw['enabled'] == true,
      id: _string(raw['id']) ?? '',
      title: _clamp(_string(raw['title']) ?? '', 120),
      message: _clamp(_string(raw['message']) ?? '', maxMessageLength),
      severity: raw['severity'] == 'warning'
          ? AnnouncementSeverity.warning
          : AnnouncementSeverity.info,
      startsAt: _time(raw['startsAt']),
      expiresAt: _time(raw['expiresAt']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppAnnouncement &&
      other.enabled == enabled &&
      other.id == id &&
      other.title == title &&
      other.message == message &&
      other.severity == severity &&
      other.startsAt == startsAt &&
      other.expiresAt == expiresAt;

  @override
  int get hashCode =>
      Object.hash(enabled, id, title, message, severity, startsAt, expiresAt);
}

/// Longest free text the app will render from the document. The server
/// enforces the same limit; this is only a guard against a bad write.
const int maxMessageLength = 280;

/// The server-owned `appOperationsConfig/public` document.
///
/// [AppOperationsConfig.fromMap] never throws: any field it cannot read
/// falls back to the value that means "normal operation". A broken document
/// can therefore never lock anybody out; only a well-formed `true` or a
/// readable version does.
@immutable
class AppOperationsConfig {
  const AppOperationsConfig({
    this.schemaVersion = 1,
    this.revision = 0,
    this.updatedAt,
    this.maintenanceEnabled = false,
    this.maintenanceMessage,
    this.minimumVersion = const PlatformValues(),
    this.recommendedVersion = const PlatformValues(),
    this.updateUrl = const PlatformValues(),
    this.disabledFeatures = const {},
    this.announcement,
  });

  /// Normal operation: nothing gated, every feature on.
  static const AppOperationsConfig defaults = AppOperationsConfig();

  final int schemaVersion;
  final int revision;
  final DateTime? updatedAt;
  final bool maintenanceEnabled;

  /// Custom maintenance copy, or null for the app's own.
  final String? maintenanceMessage;
  final PlatformValues minimumVersion;
  final PlatformValues recommendedVersion;

  /// Only `https` links survive parsing.
  final PlatformValues updateUrl;
  final Set<AppFeature> disabledFeatures;
  final AppAnnouncement? announcement;

  bool isFeatureEnabled(AppFeature feature) =>
      !disabledFeatures.contains(feature);

  /// Where [installed] stands against the published versions on [platform].
  /// An unreadable installed or published version gates nothing.
  VersionGate versionGateFor({
    required AppPlatform platform,
    required String? installed,
  }) {
    final current = SemanticVersion.tryParse(installed);
    if (current == null) {
      return VersionGate.ok;
    }
    final minimum = SemanticVersion.tryParse(
      minimumVersion.forPlatform(platform),
    );
    if (minimum != null && current < minimum) {
      return VersionGate.updateRequired;
    }
    final recommended = SemanticVersion.tryParse(
      recommendedVersion.forPlatform(platform),
    );
    if (recommended != null && current < recommended) {
      return VersionGate.updateRecommended;
    }
    return VersionGate.ok;
  }

  static AppOperationsConfig fromMap(Object? raw) {
    if (raw is! Map) {
      return defaults;
    }
    try {
      final maintenance = raw['maintenance'];
      final features = raw['features'];
      final disabled = <AppFeature>{};
      if (features is Map) {
        for (final feature in AppFeature.values) {
          if (features[feature.key] == false) {
            disabled.add(feature);
          }
        }
      }
      final message = maintenance is Map
          ? _string(maintenance['message'])
          : null;
      return AppOperationsConfig(
        schemaVersion: _int(raw['schemaVersion']) ?? 1,
        revision: _int(raw['revision']) ?? 0,
        updatedAt: _time(raw['updatedAt']),
        maintenanceEnabled:
            maintenance is Map && maintenance['enabled'] == true,
        maintenanceMessage: message == null || message.isEmpty
            ? null
            : _clamp(message, maxMessageLength),
        minimumVersion: _platformValues(raw['minimumVersion'], _version),
        recommendedVersion: _platformValues(
          raw['recommendedVersion'],
          _version,
        ),
        updateUrl: _platformValues(raw['updateUrl'], _httpsUrl),
        disabledFeatures: Set.unmodifiable(disabled),
        announcement: AppAnnouncement.fromMap(raw['announcement']),
      );
    } on Object {
      return defaults;
    }
  }

  /// JSON-safe form for the local cache; [fromMap] reads it back.
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'revision': revision,
    'updatedAt': updatedAt?.millisecondsSinceEpoch,
    'maintenance': {
      'enabled': maintenanceEnabled,
      'message': maintenanceMessage,
    },
    'minimumVersion': minimumVersion.toJson(),
    'recommendedVersion': recommendedVersion.toJson(),
    'updateUrl': updateUrl.toJson(),
    'features': {
      for (final feature in AppFeature.values)
        feature.key: isFeatureEnabled(feature),
    },
    'announcement': announcement?.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      other is AppOperationsConfig &&
      other.schemaVersion == schemaVersion &&
      other.revision == revision &&
      other.updatedAt == updatedAt &&
      other.maintenanceEnabled == maintenanceEnabled &&
      other.maintenanceMessage == maintenanceMessage &&
      other.minimumVersion == minimumVersion &&
      other.recommendedVersion == recommendedVersion &&
      other.updateUrl == updateUrl &&
      setEquals(other.disabledFeatures, disabledFeatures) &&
      other.announcement == announcement;

  @override
  int get hashCode => Object.hash(
    schemaVersion,
    revision,
    updatedAt,
    maintenanceEnabled,
    maintenanceMessage,
    minimumVersion,
    recommendedVersion,
    updateUrl,
    Object.hashAllUnordered(disabledFeatures),
    announcement,
  );
}

PlatformValues _platformValues(Object? raw, String? Function(Object?) read) {
  if (raw is! Map) {
    return const PlatformValues();
  }
  return PlatformValues(android: read(raw['android']), ios: read(raw['ios']));
}

String? _version(Object? raw) {
  final text = _string(raw);
  return SemanticVersion.tryParse(text) == null ? null : text;
}

String? _httpsUrl(Object? raw) {
  final text = _string(raw);
  if (text == null) {
    return null;
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    return null;
  }
  return text;
}

String? _string(Object? raw) => raw is String ? raw.trim() : null;

String _clamp(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

int? _int(Object? raw) => switch (raw) {
  final int value => value,
  final double value when value.isFinite => value.toInt(),
  _ => null,
};

/// Timestamps arrive as [DateTime] from Firestore (the data layer converts
/// them) and as epoch milliseconds from the local cache.
DateTime? _time(Object? raw) => switch (raw) {
  final DateTime value => value,
  final int value => DateTime.fromMillisecondsSinceEpoch(value),
  final String value => DateTime.tryParse(value),
  _ => null,
};
