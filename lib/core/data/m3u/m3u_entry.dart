class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId,
    this.tvgName,
    this.logo,
    this.group,
    this.tvgChno,
    this.catchup,
    this.catchupSource,
    this.catchupDays,
    this.userAgent,
    this.referrer,
  });

  final String name;
  final String url;
  final String? tvgId;
  final String? tvgName;
  final String? logo;
  final String? group;
  final int? tvgChno;
  final String? catchup;
  final String? catchupSource;
  final int? catchupDays;
  final String? userAgent;
  final String? referrer;
}

class M3uHeader {
  const M3uHeader({
    this.catchup,
    this.catchupSource,
    this.catchupDays,
    this.urlTvg,
  });

  static const M3uHeader empty = M3uHeader();

  final String? catchup;
  final String? catchupSource;
  final int? catchupDays;
  final String? urlTvg;
}

class ParsedChunk {
  const ParsedChunk(this.entries, this.discarded);

  final List<M3uEntry> entries;
  final int discarded;
}

class KeyedEntry {
  const KeyedEntry(this.entry, this.key, this.foldedName);

  final M3uEntry entry;
  final String key;
  final String foldedName;
}
