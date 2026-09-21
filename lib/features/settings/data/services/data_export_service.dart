import 'dart:convert';
import 'dart:io';

import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/features/settings/domain/services/file_share_port.dart';
import 'package:path_provider/path_provider.dart';

/// Result of an export: where the file landed and whether the user actually
/// received it through the platform sheet.
class DataExportResult {
  const DataExportResult({required this.path, required this.outcome});

  final String path;
  final FileShareOutcome outcome;

  /// True when the file reached somewhere the user can get at.
  bool get delivered => outcome == FileShareOutcome.shared;
}

const String _exportPrefix = 'mevora-data-export-';
const String _exportMimeType = 'application/json';

/// Downloads a privacy export package via Cloud Functions, writes it to a
/// private file, and hands that file to the platform share/save sheet.
///
/// Writing alone is not delivery: the file lives in the app's cache directory,
/// which a user cannot browse to, so the share step is part of the operation.
class DataExportService {
  DataExportService(this._callable, {required FileSharePort share})
    : _share = share;

  final BackendCallable _callable;
  final FileSharePort _share;

  /// Generates the export and offers it to the user. Throws if generation or
  /// the write fails; share outcomes are reported, not thrown.
  Future<DataExportResult> exportAndShare({String? subject}) async {
    final file = await _writeExport();
    final outcome = await _share.shareFile(
      path: file.path,
      mimeType: _exportMimeType,
      subject: subject,
    );
    return DataExportResult(path: file.path, outcome: outcome);
  }

  Future<File> _writeExport() async {
    final payload = await _callable.invoke('exportMyData');
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getTemporaryDirectory();
    await _pruneOldExports(dir);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/$_exportPrefix$stamp.json');
    await file.writeAsString(json, flush: true);
    return file;
  }

  /// Personal data should not accumulate in the cache across exports.
  Future<void> _pruneOldExports(Directory dir) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is! File) {
          continue;
        }
        final name = entity.uri.pathSegments.last;
        if (name.startsWith(_exportPrefix) && name.endsWith('.json')) {
          await entity.delete();
        }
      }
    } on FileSystemException {
      // A stale file we cannot remove must not fail the export.
    }
  }
}
