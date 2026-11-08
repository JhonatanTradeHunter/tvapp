import 'package:drift/drift.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/data/db/tables.dart';
import 'package:tvapp/core/util/pin.dart';

part 'profile_dao.g.dart';

enum BlockedKind { live, vod, series }

@DriftAccessor(tables: [Profiles, ProfileBlockedGroups])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(super.attachedDatabase);

  Stream<List<ProfileRow>> watchAll() =>
      (select(profiles)..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.id),
          ]))
          .watch();

  Future<List<ProfileRow>> all() =>
      (select(profiles)..orderBy([
            (t) => OrderingTerm.asc(t.position),
            (t) => OrderingTerm.asc(t.id),
          ]))
          .get();

  Future<ProfileRow?> byId(int id) =>
      (select(profiles)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Cria o perfil padrão quando não existe nenhum e devolve o primeiro.
  Future<ProfileRow> ensureDefault(String name) async {
    final existing = await all();
    if (existing.isNotEmpty) return existing.first;
    final id = await into(
      profiles,
    ).insert(ProfilesCompanion.insert(name: name));
    return (await byId(id))!;
  }

  Future<int> createProfile({
    required String name,
    required int colorIndex,
    required bool isKids,
    int? maxAge,
    String? pin,
  }) async {
    final count = (await all()).length;
    return into(profiles).insert(
      ProfilesCompanion.insert(
        name: name,
        colorIndex: Value(colorIndex),
        isKids: Value(isKids),
        maxAge: Value(isKids ? maxAge : null),
        position: Value(count),
        pinHash: Value(_hashOrNull(pin)?.$1),
        pinSalt: Value(_hashOrNull(pin)?.$2),
      ),
    );
  }

  Future<void> updateProfile(
    int id, {
    required String name,
    required int colorIndex,
    required bool isKids,
    int? maxAge,
  }) => (update(profiles)..where((t) => t.id.equals(id))).write(
    ProfilesCompanion(
      name: Value(name),
      colorIndex: Value(colorIndex),
      isKids: Value(isKids),
      maxAge: Value(isKids ? maxAge : null),
    ),
  );

  /// [pin] nulo remove o PIN.
  Future<void> setPin(int id, String? pin) {
    final hashed = _hashOrNull(pin);
    return (update(profiles)..where((t) => t.id.equals(id))).write(
      ProfilesCompanion(pinHash: Value(hashed?.$1), pinSalt: Value(hashed?.$2)),
    );
  }

  Future<void> deleteProfile(int id) =>
      (delete(profiles)..where((t) => t.id.equals(id))).go();

  Stream<Set<String>> watchBlocked(int profileId, BlockedKind kind) =>
      (select(profileBlockedGroups)..where(
            (t) => t.profileId.equals(profileId) & t.kind.equals(kind.name),
          ))
          .watch()
          .map((rows) => <String>{for (final r in rows) r.groupName});

  Future<void> setBlocked(
    int profileId,
    BlockedKind kind,
    Set<String> groups,
  ) async {
    await transaction(() async {
      await (delete(profileBlockedGroups)..where(
            (t) => t.profileId.equals(profileId) & t.kind.equals(kind.name),
          ))
          .go();
      await batch((b) {
        b.insertAll(profileBlockedGroups, <ProfileBlockedGroupsCompanion>[
          for (final g in groups)
            ProfileBlockedGroupsCompanion.insert(
              profileId: profileId,
              kind: kind.name,
              groupName: g,
            ),
        ]);
      });
    });
  }

  static (String, String)? _hashOrNull(String? pin) {
    if (pin == null || !PinHasher.isValid(pin)) return null;
    final salt = PinHasher.newSalt();
    return (PinHasher.hash(pin, salt), salt);
  }
}
