import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

void agentDebugLogImpl({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  if (!kDebugMode) return;

  final payload = <String, Object?>{
    'sessionId': '470400',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  // ignore: avoid_print
  print('AGENT_DBG ${jsonEncode(payload)}');
  try {
    // Workspace-relative when running from repo; ignored on device sandboxes.
    File('debug-470400.log').writeAsStringSync(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
