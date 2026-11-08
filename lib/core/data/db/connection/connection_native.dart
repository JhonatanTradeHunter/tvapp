import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SQLite nativo num isolate de fundo, arquivo na pasta de suporte do app.
DatabaseConnection openConnection() {
  return DatabaseConnection(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      final file = File(p.join(dir.path, 'tvapp.sqlite'));
      return NativeDatabase.createInBackground(file);
    }),
  );
}
