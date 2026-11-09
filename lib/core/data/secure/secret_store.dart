import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/playlist_source.dart';

/// Guarda segredos fora do SQLite: Keystore no Android, Keychain no iOS.
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);

  static String xtreamPasswordKey(int sourceId) => 'xtream.pass.$sourceId';
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Uma chave corrompida no Keystore não pode derrubar o app: sem a senha,
  /// a fonte só falha na autenticação e o usuário digita de novo.
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      debugPrint('secure storage read: $e');
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('secure storage delete: $e');
    }
  }
}

/// Para testes e para a demo web, onde o armazenamento do navegador pode não
/// responder dentro do iframe.
class MemorySecretStore implements SecretStore {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Credenciais Xtream da linha, com a senha vinda do [SecretStore]. A
/// coluna antiga só é lida enquanto [moveXtreamPasswords] não rodou.
Future<XtreamCredentials?> xtreamCredentialsFor(
  SourceRow row,
  SecretStore store,
) async {
  final host = row.xtreamHost;
  if (row.kind != SourceKind.xtream || host == null) return null;
  final password =
      await store.read(SecretStore.xtreamPasswordKey(row.id)) ??
      row.xtreamPass ??
      '';
  return XtreamCredentials(
    host: host,
    port: row.xtreamPort,
    username: row.xtreamUser ?? '',
    password: password,
  );
}

/// Move as senhas Xtream gravadas no SQLite (antes da fase 6) para o
/// [SecretStore] e apaga a coluna. Cada senha só sai do banco depois de
/// gravada; se a gravação falhar, fica para a próxima abertura. Devolve
/// quantas foram movidas.
Future<int> moveXtreamPasswords(AppDatabase db, SecretStore store) async {
  final rows = await (db.select(
    db.sources,
  )..where((t) => t.xtreamPass.isNotNull())).get();
  var moved = 0;
  for (final row in rows) {
    final password = row.xtreamPass;
    if (password == null) continue;
    try {
      await store.write(SecretStore.xtreamPasswordKey(row.id), password);
    } catch (e) {
      debugPrint('senha da fonte ${row.id} continua no banco: $e');
      continue;
    }
    await (db.update(db.sources)..where((t) => t.id.equals(row.id))).write(
      const SourcesCompanion(xtreamPass: Value(null)),
    );
    moved++;
  }
  // Sem VACUUM, o texto antigo pode continuar nas páginas livres do arquivo.
  if (moved > 0) await db.customStatement('VACUUM');
  return moved;
}
