import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/settings/data/services/data_export_service.dart';
import 'package:mevora/features/settings/data/services/share_plus_file_share.dart';
import 'package:mevora/features/settings/domain/services/file_share_port.dart';

class _FakeCallable implements BackendCallable {
  _FakeCallable({this.payload = const {'uid': 'u1'}, this.error});

  final Map<String, dynamic> payload;
  final Object? error;
  final List<String> calls = [];

  @override
  Future<Map<String, dynamic>> invoke(
    String name, [
    Map<String, dynamic>? data,
  ]) async {
    calls.add(name);
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return payload;
  }
}

class _RecordingShare implements FileSharePort {
  _RecordingShare({this.outcome = FileShareOutcome.shared, this.error});

  final FileShareOutcome outcome;
  final Object? error;
  String? sharedPath;
  String? sharedMime;
  String? sharedSubject;
  int calls = 0;

  @override
  Future<FileShareOutcome> shareFile({
    required String path,
    required String mimeType,
    String? subject,
  }) async {
    calls += 1;
    sharedPath = path;
    sharedMime = mimeType;
    sharedSubject = subject;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return outcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mevora-export-test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  List<File> exportsIn(Directory dir) => dir
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith('mevora-data-export-'))
      .toList();

  test('writes the export and hands it to the share sheet', () async {
    final callable = _FakeCallable(payload: {'uid': 'u1', 'profile': {'a': 1}});
    final share = _RecordingShare();

    final result = await DataExportService(
      callable,
      share: share,
    ).exportAndShare(subject: 'My Mevora data export');

    expect(callable.calls, ['exportMyData']);
    expect(share.calls, 1, reason: 'the file must actually be delivered');
    expect(share.sharedPath, result.path);
    expect(share.sharedMime, 'application/json');
    expect(share.sharedSubject, 'My Mevora data export');
    expect(result.outcome, FileShareOutcome.shared);
    expect(result.delivered, isTrue);

    final file = File(result.path);
    expect(file.existsSync(), isTrue);
    expect(jsonDecode(file.readAsStringSync()), {
      'uid': 'u1',
      'profile': {'a': 1},
    });
  });

  test('a dismissed sheet is reported, not treated as success', () async {
    final share = _RecordingShare(outcome: FileShareOutcome.dismissed);

    final result = await DataExportService(
      _FakeCallable(),
      share: share,
    ).exportAndShare();

    expect(result.outcome, FileShareOutcome.dismissed);
    expect(result.delivered, isFalse);
    // The file is still on disk so the user can retry the share.
    expect(File(result.path).existsSync(), isTrue);
  });

  test('an unavailable sheet is reported', () async {
    final result = await DataExportService(
      _FakeCallable(),
      share: _RecordingShare(outcome: FileShareOutcome.unavailable),
    ).exportAndShare();

    expect(result.outcome, FileShareOutcome.unavailable);
    expect(result.delivered, isFalse);
  });

  test('generation failure throws and never invokes the share sheet', () async {
    final share = _RecordingShare();
    final service = DataExportService(
      _FakeCallable(error: StateError('backend down')),
      share: share,
    );

    await expectLater(service.exportAndShare(), throwsA(isA<StateError>()));
    expect(share.calls, 0);
    expect(exportsIn(tempDir), isEmpty);
  });

  test('a share failure propagates rather than claiming delivery', () async {
    final service = DataExportService(
      _FakeCallable(),
      share: _RecordingShare(error: const FileSystemException('gone')),
    );

    await expectLater(
      service.exportAndShare(),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('previous exports are pruned so personal data does not pile up', () async {
    final stale = File('${tempDir.path}/mevora-data-export-old.json')
      ..writeAsStringSync('{"old":true}');
    final unrelated = File('${tempDir.path}/keep-me.txt')
      ..writeAsStringSync('x');

    final result = await DataExportService(
      _FakeCallable(),
      share: _RecordingShare(),
    ).exportAndShare();

    expect(stale.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue, reason: 'only exports are pruned');
    final remaining = exportsIn(tempDir)
        .map((f) => f.uri.pathSegments.last)
        .toList();
    expect(remaining, [File(result.path).uri.pathSegments.last]);
  });

  group('SharePlusFileShare', () {
    test('refuses a missing file before touching the platform', () async {
      await expectLater(
        const SharePlusFileShare().shareFile(
          path: '${tempDir.path}/does-not-exist.json',
          mimeType: 'application/json',
        ),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
