import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Session-scoped debug logger for agent-driven investigation (debug builds only).
abstract final class AgentDebugLog {
  static const _sessionId = '80971b';
  static const _ingestPath =
      '/ingest/8ea8ddd4-7eed-4eaa-aca9-ce0e91e100fc';

  static String get _host =>
      Platform.isAndroid ? '10.0.2.2' : '127.0.0.1';

  static void log({
    required String location,
    required String message,
    required String hypothesisId,
    Map<String, Object?> data = const {},
    String runId = 'chat-image',
  }) {
    if (!kDebugMode) {
      return;
    }
    final payload = <String, dynamic>{
      'sessionId': _sessionId,
      'runId': runId,
      'hypothesisId': hypothesisId,
      'location': location,
      'message': message,
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
    debugPrint('agent-debug ${jsonEncode(payload)}');
    unawaited(_send(payload));
  }

  static Future<void> _send(Map<String, dynamic> payload) async {
    try {
      final client = HttpClient();
      final request = await client.post(_host, 7720, _ingestPath);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('X-Debug-Session-Id', _sessionId);
      request.add(utf8.encode(jsonEncode(payload)));
      await request.close();
      client.close(force: true);
    } on Object {
      // Best-effort only.
    }
  }
}
