import 'dart:convert';
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

void agentDebugLogImpl({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  // Debug-session logging: keep active even in profile/release web so phone/desktop
  // Pages builds can POST to the local ingest when opened on this machine.
  final payload = <String, Object?>{
    'sessionId': 'f31c5a',
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  final encoded = jsonEncode(payload);
  // ignore: avoid_print
  print('AGENT_DBG $encoded');

  try {
    final existing = html.window.localStorage['agent_dbg_f31c5a'] ?? '[]';
    final list = (jsonDecode(existing) as List).toList();
    list.add(payload);
    if (list.length > 80) {
      list.removeRange(0, list.length - 80);
    }
    html.window.localStorage['agent_dbg_f31c5a'] = jsonEncode(list);
  } catch (_) {}

  try {
    html.HttpRequest.request(
      'http://127.0.0.1:7658/ingest/da7f666c-0ef2-4f7e-8d57-09a6cac8951b',
      method: 'POST',
      requestHeaders: {
        'Content-Type': 'application/json',
        'X-Debug-Session-Id': 'f31c5a',
      },
      sendData: encoded,
    );
  } catch (_) {}
}
