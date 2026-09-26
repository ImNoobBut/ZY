import 'dart:convert';
import 'dart:io';

void agentDebugLogImpl({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  final payload = <String, Object?>{
    'sessionId': 'f31c5a',
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
    File('debug-f31c5a.log').writeAsStringSync(
      '${jsonEncode(payload)}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}
