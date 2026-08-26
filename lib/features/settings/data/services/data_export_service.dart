import 'dart:convert';
import 'dart:io';

import 'package:mevora/core/network/backend_callable.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads a privacy export package via Cloud Functions and writes JSON
/// to a local file the user can copy/share.
class DataExportService {
  DataExportService(this._callable);

  final BackendCallable _callable;

  Future<String> exportToFile() async {
    final payload = await _callable.invoke('exportMyData');
    final json = const JsonEncoder.withIndent('  ').convert(payload);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final file = File('${dir.path}/mevora-data-export-$stamp.json');
    await file.writeAsString(json, flush: true);
    return file.path;
  }
}
