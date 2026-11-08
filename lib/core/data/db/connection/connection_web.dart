import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';

/// SQLite em WebAssembly. `sqlite3.wasm` e `drift_worker.js` ficam na raiz
/// do site (o workflow web os copia para `web/`).
DatabaseConnection openConnection() {
  return DatabaseConnection.delayed(
    Future(() async {
      final result = await WasmDatabase.open(
        databaseName: 'tvapp',
        sqlite3Uri: Uri.parse('sqlite3.wasm'),
        driftWorkerUri: Uri.parse('drift_worker.js'),
      );
      return result.resolvedExecutor;
    }),
  );
}
