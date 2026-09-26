import 'agent_debug_log_stub.dart'
    if (dart.library.html) 'agent_debug_log_web.dart' as impl;
import 'package:flutter/foundation.dart';

/// Session debug NDJSON (ingest / file). Do not log secrets.
/// No-op in release builds.
void agentDebugLog({
  required String hypothesisId,
  required String location,
  required String message,
  Map<String, Object?> data = const {},
  String runId = 'pre-fix',
}) {
  if (!kDebugMode) return;
  impl.agentDebugLogImpl(
    hypothesisId: hypothesisId,
    location: location,
    message: message,
    data: data,
    runId: runId,
  );
}
