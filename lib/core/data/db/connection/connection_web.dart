import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:sqlite3/wasm.dart';
import 'package:tvapp/features/demo/demo_bootstrap.dart';

/// Limite para o SQLite em WebAssembly ficar pronto. Dentro de um iframe
/// sandbox, OPFS e IndexedDB podem não responder nunca.
const Duration webOpenTimeout = Duration(seconds: 10);

/// SQLite em WebAssembly. `sqlite3.wasm` e `drift_worker.js` ficam na raiz
/// do site (o workflow web os copia para `web/`).
///
/// No modo demo o banco fica em memória, sem worker e sem armazenamento: a
/// demo recria os dados a cada abertura.
DatabaseConnection openConnection() {
  return DatabaseConnection.delayed(
    (kDemo ? _openInMemory() : _openPersistent()).timeout(webOpenTimeout),
  );
}

Future<DatabaseConnection> _openInMemory() async {
  final sqlite3 = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  sqlite3.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  return DatabaseConnection(WasmDatabase.inMemory(sqlite3));
}

Future<DatabaseConnection> _openPersistent() async {
  final result = await WasmDatabase.open(
    databaseName: 'tvapp',
    sqlite3Uri: Uri.parse('sqlite3.wasm'),
    driftWorkerUri: Uri.parse('drift_worker.js'),
  );
  return result.resolvedExecutor;
}
