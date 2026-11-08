import 'package:tvapp/core/data/db/daos/profile_dao.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/util/normalize.dart';

/// O que o perfil ativo pode ver. Grupos escondidos valem para qualquer
/// perfil. No perfil infantil, também somem grupos e canais com cara de
/// conteúdo adulto, e programas acima de [maxAge] pedem PIN para tocar.
class ParentalPolicy {
  const ParentalPolicy({
    this.isKids = false,
    this.maxAge,
    this.blockedLive = const <String>{},
    this.blockedVod = const <String>{},
    this.blockedSeries = const <String>{},
  });

  static const ParentalPolicy unrestricted = ParentalPolicy();

  final bool isKids;
  final int? maxAge;
  final Set<String> blockedLive;
  final Set<String> blockedVod;
  final Set<String> blockedSeries;

  static final RegExp _adult = RegExp(
    r'(^|[^a-z0-9])(adult[a-z]*|xxx|porn[a-z]*|erotic[a-z]*|erotico|sexy|hot|18 ?\+|\+ ?18)([^a-z0-9]|$)',
  );

  /// Heurística por nome, já sem acento e em minúsculas.
  static bool looksAdult(String name) => _adult.hasMatch(foldName(name));

  Set<String> _blocked(BlockedKind kind) {
    switch (kind) {
      case BlockedKind.live:
        return blockedLive;
      case BlockedKind.vod:
        return blockedVod;
      case BlockedKind.series:
        return blockedSeries;
    }
  }

  bool allowsGroup(BlockedKind kind, String group) {
    if (_blocked(kind).contains(group)) return false;
    return !(isKids && looksAdult(group));
  }

  /// Para itens de catálogo e canais: grupo liberado e, no infantil, nome
  /// sem marca de conteúdo adulto.
  bool allowsItem(BlockedKind kind, String group, String name) =>
      allowsGroup(kind, group) && !(isKids && looksAdult(name));

  bool allowsChannel(Channel channel) =>
      allowsItem(BlockedKind.live, channel.group, channel.name);

  /// Programa sem classificação passa; o limite só vale no perfil infantil.
  bool allowsProgramme(int? ageRating) {
    final limit = maxAge;
    if (!isKids || limit == null || ageRating == null) return true;
    return ageRating <= limit;
  }
}
