class ChannelGroup {
  const ChannelGroup({required this.name, required this.count});

  final String name;
  final int count;
}

class GroupFilter {
  const GroupFilter.all() : name = null, favoritesOnly = false, recent = false;

  const GroupFilter.favorites()
    : name = null,
      favoritesOnly = true,
      recent = false;

  /// Canais abertos por último no perfil, do mais recente ao mais antigo.
  const GroupFilter.recent()
    : name = null,
      favoritesOnly = false,
      recent = true;

  const GroupFilter.named(String this.name)
    : favoritesOnly = false,
      recent = false;

  final String? name;
  final bool favoritesOnly;
  final bool recent;

  bool get isAll => name == null && !favoritesOnly && !recent;

  @override
  bool operator ==(Object other) =>
      other is GroupFilter &&
      other.name == name &&
      other.favoritesOnly == favoritesOnly &&
      other.recent == recent;

  @override
  int get hashCode => Object.hash(name, favoritesOnly, recent);
}
