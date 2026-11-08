enum LiveSort { number, alpha, favorites }

class Channel {
  const Channel({
    required this.id,
    required this.sourceId,
    required this.channelKey,
    required this.position,
    required this.name,
    required this.group,
    required this.streamUrl,
    this.tvgId,
    this.logo,
    this.number,
    this.streamUrlResolved,
    this.userAgent,
    this.referrer,
    this.catchup,
    this.catchupSource,
    this.catchupDays,
    this.isFavorite = false,
  });

  final int id;
  final int sourceId;
  final String channelKey;
  final int position;
  final String name;
  final String group;
  final String streamUrl;
  final String? tvgId;
  final String? logo;
  final int? number;
  final String? streamUrlResolved;
  final String? userAgent;
  final String? referrer;
  final String? catchup;
  final String? catchupSource;
  final int? catchupDays;
  final bool isFavorite;

  String get playbackUrl => streamUrlResolved ?? streamUrl;

  int get displayNumber => number ?? position + 1;

  Map<String, String> get httpHeaders {
    final headers = <String, String>{};
    final ua = userAgent;
    final ref = referrer;
    if (ua != null && ua.isNotEmpty) headers['User-Agent'] = ua;
    if (ref != null && ref.isNotEmpty) headers['Referer'] = ref;
    return headers;
  }

  @override
  bool operator ==(Object other) =>
      other is Channel && other.id == id && other.isFavorite == isFavorite;

  @override
  int get hashCode => Object.hash(id, isFavorite);
}
