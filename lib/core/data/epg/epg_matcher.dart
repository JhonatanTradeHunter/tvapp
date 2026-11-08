import 'package:tvapp/core/util/normalize.dart';

enum EpgMatchConfidence {
  /// `tvg-id` do canal igual ao id do XMLTV.
  exact,

  /// Casado pelo nome normalizado. Pode errar; a UI sinaliza.
  name,
}

class EpgMatch {
  const EpgMatch(this.xmltvId, this.confidence);

  final String xmltvId;
  final EpgMatchConfidence confidence;

  bool get isApproximate => confidence == EpgMatchConfidence.name;
}

class EpgChannelInfo {
  const EpgChannelInfo({required this.id, required this.normalizedName});

  final String id;
  final String normalizedName;
}

/// Casamento canal → EPG. Regra: `tvg-id` primeiro; nome normalizado só
/// como fallback e só quando o nome aponta para um único canal do XMLTV.
class EpgMatcher {
  EpgMatcher(Iterable<EpgChannelInfo> channels) {
    final ambiguous = <String>{};
    for (final c in channels) {
      _ids.add(c.id);
      final key = c.normalizedName;
      if (key.isEmpty || ambiguous.contains(key)) continue;
      final existing = _byName[key];
      if (existing == null) {
        _byName[key] = c.id;
      } else if (existing != c.id) {
        _byName.remove(key);
        ambiguous.add(key);
      }
    }
  }

  final Set<String> _ids = <String>{};
  final Map<String, String> _byName = <String, String>{};

  bool get isEmpty => _ids.isEmpty;

  EpgMatch? match({required String? tvgId, required String name}) {
    final id = (tvgId ?? '').trim().toLowerCase();
    if (id.isNotEmpty) {
      // XMLTV sem <channel> ainda pode trazer programas para esse id.
      if (_ids.isEmpty || _ids.contains(id)) {
        return EpgMatch(id, EpgMatchConfidence.exact);
      }
    }
    final key = normalizeForMatch(name);
    if (key.isEmpty) return null;
    final byName = _byName[key];
    if (byName != null) return EpgMatch(byName, EpgMatchConfidence.name);
    return null;
  }
}
