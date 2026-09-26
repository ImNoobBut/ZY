/// Time-of-day greeting using the device's local clock.
String greetingFor(DateTime local, String name) {
  final trimmed = name.trim();
  final label = trimmed.isEmpty ? 'friend' : trimmed;
  final hour = local.hour;
  final phrase = hour < 12
      ? 'Good morning'
      : hour < 17
          ? 'Good afternoon'
          : 'Good evening';
  return '$phrase, $label';
}
