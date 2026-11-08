/// Leitura tolerante do JSON do Xtream Codes. Os painéis variam: ids chegam
/// como número ou string, números como string, listas como mapas
/// indexados, e campos ausentes como null, "" ou false.
class JsonRead {
  JsonRead._();

  static Map<String, Object?> map(Object? value) {
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries) '${entry.key}': entry.value,
      };
    }
    return const <String, Object?>{};
  }

  static List<Object?> list(Object? value) {
    if (value is List) return value;
    if (value is Map) return value.values.toList();
    return const <Object?>[];
  }

  static String? string(Object? value) {
    if (value == null || value == false) return null;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is num || value is bool) return '$value';
    return null;
  }

  static int? integer(Object? value) {
    if (value is int) return value;
    if (value is double) return value.isFinite ? value.round() : null;
    if (value is bool) return value ? 1 : 0;
    if (value is String) {
      final trimmed = value.trim();
      return int.tryParse(trimmed) ?? double.tryParse(trimmed)?.round();
    }
    return null;
  }

  static double? number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static bool flag(Object? value) {
    if (value is bool) return value;
    if (integer(value) == 1) return true;
    return string(value)?.toLowerCase() == 'true';
  }

  /// Segundos desde a época, em UTC. Zero ou inválido vira null.
  static DateTime? epoch(Object? value) {
    final seconds = integer(value);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static List<String> strings(Object? value) => <String>[
    for (final item in list(value))
      if (string(item) case final s?) s,
  ];
}
