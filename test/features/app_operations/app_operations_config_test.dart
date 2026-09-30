import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/features/app_operations/domain/app_operations_config.dart';
import 'package:mevora/features/app_operations/domain/app_operations_gate.dart';
import 'package:mevora/features/app_operations/domain/semantic_version.dart';

void main() {
  group('SemanticVersion', () {
    test('parses x.y.z and ignores a build suffix', () {
      expect(SemanticVersion.tryParse('1.2.3'), const SemanticVersion(1, 2, 3));
      expect(
        SemanticVersion.tryParse('1.2.3+45'),
        const SemanticVersion(1, 2, 3),
      );
      expect(SemanticVersion.tryParse(' 2.0 '), const SemanticVersion(2, 0, 0));
      expect(SemanticVersion.tryParse('3'), const SemanticVersion(3, 0, 0));
    });

    test('anything unreadable is not a version', () {
      for (final raw in <Object?>[
        null,
        '',
        '+2',
        'abc',
        '1.2.x',
        '1..2',
        '1.2.3.4',
        '1.2.3-beta',
        '-1.0.0',
        12,
      ]) {
        expect(SemanticVersion.tryParse(raw), isNull, reason: '$raw');
      }
    });

    test('an installed flavor build is its release version', () {
      // Found on a development APK in runtime QA: versionName "1.0.1-dev"
      // was unreadable, so a raised minimum never gated dev or staging builds.
      expect(
        SemanticVersion.tryParseInstalled('1.0.1-dev'),
        const SemanticVersion(1, 0, 1),
      );
      expect(
        SemanticVersion.tryParseInstalled('1.0.1-staging+2'),
        const SemanticVersion(1, 0, 1),
      );
      expect(
        SemanticVersion.tryParseInstalled('1.0.1'),
        const SemanticVersion(1, 0, 1),
      );
      expect(SemanticVersion.tryParseInstalled('dev'), isNull);
      expect(SemanticVersion.tryParseInstalled(null), isNull);
      // Published versions stay strict.
      expect(SemanticVersion.tryParse('1.0.1-dev'), isNull);
      final config = AppOperationsConfig.fromMap(const {
        'minimumVersion': {'android': '9.0.0'},
      });
      expect(
        config.versionGateFor(
          platform: AppPlatform.android,
          installed: '1.0.1-dev',
        ),
        VersionGate.updateRequired,
      );
    });

    test('compares numerically, not as text', () {
      final a = SemanticVersion.tryParse('1.10.0')!;
      final b = SemanticVersion.tryParse('1.9.9')!;
      expect(b < a, isTrue);
      expect(a < b, isFalse);
      expect(
        SemanticVersion.tryParse(
          '1.0.1',
        )!.compareTo(SemanticVersion.tryParse('1.0.1+9')!),
        0,
      );
    });
  });

  group('AppOperationsConfig.fromMap', () {
    test('missing, empty or wrong-typed input is normal operation', () {
      for (final raw in <Object?>[null, 'x', 42, <String, Object?>{}]) {
        final config = AppOperationsConfig.fromMap(raw);
        expect(config.maintenanceEnabled, isFalse);
        expect(config.announcement, isNull);
        for (final feature in AppFeature.values) {
          expect(config.isFeatureEnabled(feature), isTrue);
        }
        expect(
          config.versionGateFor(
            platform: AppPlatform.android,
            installed: '0.0.1',
          ),
          VersionGate.ok,
        );
      }
    });

    test('invalid fields fall back instead of throwing', () {
      final config = AppOperationsConfig.fromMap({
        'schemaVersion': 'one',
        'revision': 'x',
        'maintenance': {'enabled': 'yes', 'message': 7},
        'minimumVersion': {'android': 'latest', 'ios': 3},
        'updateUrl': {
          'android': 'http://play.example/app',
          'ios': 'javascript:alert(1)',
        },
        'features': {'boost': 'false', 'calls': 0},
        'announcement': 'hello',
      });
      expect(config.schemaVersion, 1);
      expect(config.revision, 0);
      expect(config.maintenanceEnabled, isFalse);
      expect(config.maintenanceMessage, isNull);
      expect(config.minimumVersion, const PlatformValues());
      expect(config.updateUrl, const PlatformValues());
      expect(config.isFeatureEnabled(AppFeature.boost), isTrue);
      expect(config.isFeatureEnabled(AppFeature.calls), isTrue);
      expect(config.announcement, isNull);
    });

    test('reads a complete document', () {
      final config = AppOperationsConfig.fromMap({
        'schemaVersion': 1,
        'revision': 7,
        'updatedAt': DateTime.utc(2026, 9, 30),
        'maintenance': {'enabled': true, 'message': '  Back at 10:00  '},
        'minimumVersion': {'android': '1.2.0', 'ios': null},
        'recommendedVersion': {'android': '1.3.0', 'ios': '1.3.0'},
        'updateUrl': {
          'android': 'https://play.google.com/store/apps/details?id=x',
          'ios': null,
        },
        'features': {'boost': false, 'picks': false},
        'announcement': {
          'enabled': true,
          'id': 'a1',
          'title': 'Heads up',
          'message': '<b>not html</b>',
          'severity': 'warning',
          'startsAt': null,
          'expiresAt': DateTime.utc(2026, 10, 1),
        },
      });
      expect(config.revision, 7);
      expect(config.maintenanceEnabled, isTrue);
      expect(config.maintenanceMessage, 'Back at 10:00');
      expect(config.minimumVersion.android, '1.2.0');
      expect(config.updateUrl.forPlatform(AppPlatform.android), isNotNull);
      expect(config.updateUrl.forPlatform(AppPlatform.ios), isNull);
      expect(config.isFeatureEnabled(AppFeature.boost), isFalse);
      expect(config.isFeatureEnabled(AppFeature.picks), isFalse);
      expect(config.isFeatureEnabled(AppFeature.calls), isTrue);
      expect(config.isFeatureEnabled(AppFeature.spotify), isTrue);
      expect(config.isFeatureEnabled(AppFeature.humorLab), isTrue);
      final announcement = config.announcement!;
      expect(announcement.severity, AnnouncementSeverity.warning);
      expect(announcement.message, '<b>not html</b>');
    });

    test('long free text is clamped', () {
      final config = AppOperationsConfig.fromMap({
        'maintenance': {'enabled': true, 'message': 'x' * 1000},
      });
      expect(config.maintenanceMessage!.length, maxMessageLength);
    });

    test('survives the cache round trip', () {
      final original = AppOperationsConfig.fromMap({
        'revision': 3,
        'updatedAt': DateTime.fromMillisecondsSinceEpoch(1700000000000),
        'maintenance': {'enabled': true, 'message': 'Soon'},
        'minimumVersion': {'android': '1.0.0', 'ios': '1.1.0'},
        'recommendedVersion': {'android': '1.2.0'},
        'updateUrl': {'ios': 'https://apps.apple.com/app/id1'},
        'features': {'calls': false},
        'announcement': {
          'enabled': true,
          'id': 'x',
          'title': 't',
          'message': 'm',
          'severity': 'info',
          'startsAt': DateTime.fromMillisecondsSinceEpoch(1700000000000),
          'expiresAt': null,
        },
      });
      expect(AppOperationsConfig.fromMap(original.toJson()), original);
    });
  });

  group('version gate', () {
    const config = AppOperationsConfig(
      minimumVersion: PlatformValues(android: '1.2.0', ios: '2.0.0'),
      recommendedVersion: PlatformValues(android: '1.4.0'),
    );

    VersionGate gate(String? installed, [AppPlatform p = AppPlatform.android]) {
      return config.versionGateFor(platform: p, installed: installed);
    }

    test('below the minimum is required, below recommended is a nudge', () {
      expect(gate('1.1.9'), VersionGate.updateRequired);
      expect(gate('1.2.0'), VersionGate.updateRecommended);
      expect(gate('1.3.9+2'), VersionGate.updateRecommended);
      expect(gate('1.4.0'), VersionGate.ok);
      expect(gate('2.0.0'), VersionGate.ok);
    });

    test('each platform reads its own values', () {
      expect(gate('1.9.0', AppPlatform.ios), VersionGate.updateRequired);
      expect(gate('2.0.0', AppPlatform.ios), VersionGate.ok);
      expect(gate('0.0.1', AppPlatform.other), VersionGate.ok);
    });

    test('an unknown installed version gates nothing', () {
      expect(gate(null), VersionGate.ok);
      expect(gate('dev'), VersionGate.ok);
    });

    test('update required wins over maintenance', () {
      const both = AppOperationsConfig(maintenanceEnabled: true);
      expect(
        resolveAppOperationsGate(
          config: both,
          versionGate: VersionGate.updateRequired,
        ),
        AppOperationsGate.updateRequired,
      );
      expect(
        resolveAppOperationsGate(config: both, versionGate: VersionGate.ok),
        AppOperationsGate.maintenance,
      );
      expect(
        resolveAppOperationsGate(
          config: AppOperationsConfig.defaults,
          versionGate: VersionGate.updateRecommended,
        ),
        AppOperationsGate.normal,
      );
    });
  });

  group('announcement window', () {
    final start = DateTime(2026, 10, 1, 9);
    final end = DateTime(2026, 10, 1, 18);
    AppAnnouncement announcement({
      bool enabled = true,
      String id = 'a',
      String message = 'm',
      DateTime? startsAt,
      DateTime? expiresAt,
    }) => AppAnnouncement(
      enabled: enabled,
      id: id,
      message: message,
      startsAt: startsAt,
      expiresAt: expiresAt,
    );

    test('is half-open: from startsAt, until (not at) expiresAt', () {
      final a = announcement(startsAt: start, expiresAt: end);
      expect(a.isActiveAt(start.subtract(const Duration(seconds: 1))), isFalse);
      expect(a.isActiveAt(start), isTrue);
      expect(a.isActiveAt(end.subtract(const Duration(seconds: 1))), isTrue);
      expect(a.isActiveAt(end), isFalse);
    });

    test('missing bounds are open', () {
      expect(announcement().isActiveAt(DateTime(2000)), isTrue);
      expect(announcement(startsAt: start).isActiveAt(DateTime(2100)), isTrue);
      expect(announcement(expiresAt: end).isActiveAt(DateTime(2000)), isTrue);
    });

    test('disabled, id-less or empty announcements never show', () {
      final now = DateTime(2026, 10, 1, 12);
      expect(announcement(enabled: false).isActiveAt(now), isFalse);
      expect(announcement(id: '').isActiveAt(now), isFalse);
      expect(announcement(message: '').isActiveAt(now), isFalse);
    });

    test('knows its next boundary', () {
      final a = announcement(startsAt: start, expiresAt: end);
      expect(a.nextBoundaryAfter(DateTime(2026, 10, 1, 8)), start);
      expect(a.nextBoundaryAfter(DateTime(2026, 10, 1, 12)), end);
      expect(a.nextBoundaryAfter(DateTime(2026, 10, 2)), isNull);
    });
  });
}
