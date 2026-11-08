class ChannelGroup {
  const ChannelGroup({required this.name, required this.count});

  final String name;
  final int count;
}

class GroupFilter {
  const GroupFilter.all() : name = null, favoritesOnly = false;

  const GroupFilter.favorites() : name = null, favoritesOnly = true;

  const GroupFilter.named(String this.name) : favoritesOnly = false;

  final String? name;
  final bool favoritesOnly;

  bool get isAll => name == null && !favoritesOnly;

  @override
  bool operator ==(Object other) =>
      other is GroupFilter &&
      other.name == name &&
      other.favoritesOnly == favoritesOnly;

  @override
  int get hashCode => Object.hash(name, favoritesOnly);
}
