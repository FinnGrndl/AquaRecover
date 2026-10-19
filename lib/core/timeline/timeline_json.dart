/// Lenient readers shared by the timeline model's `fromJson` factories, so a
/// project with a missing or malformed field loads with that field's default
/// instead of failing as a whole.
library;

/// The enum value called [name], or [fallback] when there is none.
T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}

/// `json[key]` as a double, or [fallback] when it is missing or not a number.
double jsonDouble(Map<String, Object?> json, String key, double fallback) {
  final value = json[key];
  return value is num && value.isFinite ? value.toDouble() : fallback;
}

/// `json[key]` as a double, or `null` when it is missing or not a number.
double? jsonOptionalDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}

/// `json[key]` as an int, or [fallback] when it is missing or not a number.
int jsonInt(Map<String, Object?> json, String key, int fallback) {
  final value = json[key];
  return value is num && value.isFinite ? value.toInt() : fallback;
}

/// `json[key]` as a string map, or `null` when it is not a map.
Map<String, Object?>? jsonMap(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is Map ? value.cast<String, Object?>() : null;
}

/// Every map in the list at `json[key]`; anything else is skipped.
Iterable<Map<String, Object?>> jsonMaps(
  Map<String, Object?> json,
  String key,
) sync* {
  final value = json[key];
  if (value is! List) return;
  for (final item in value) {
    if (item is Map) yield item.cast<String, Object?>();
  }
}
