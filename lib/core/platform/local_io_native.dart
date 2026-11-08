import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tvapp/core/models/playlist_source.dart';

const bool localFilesSupported = true;

/// Bytes do arquivo e tamanho total.
Future<(Stream<List<int>>, int)> openLocalFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw const SourceException(SourceError.notFound);
  }
  return (file.openRead(), await file.length());
}

/// Tamanho e primeiros [maxBytes] bytes, ou null se o arquivo não existe.
Future<(int, List<int>)?> probeLocalFile(String path, int maxBytes) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final head = <int>[];
  await for (final chunk in file.openRead(0, maxBytes)) {
    head.addAll(chunk);
  }
  return (await file.length(), head);
}

Future<Directory> _playlistDir() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'playlists'));
  await dir.create(recursive: true);
  return dir;
}

/// Grava por stream na pasta do app e devolve o caminho.
Future<String> persistPickedFile(String name, Stream<List<int>> bytes) async {
  final dir = await _playlistDir();
  final safeName = p.basename(name).replaceAll(RegExp(r'[^\w.\-]'), '_');
  final target = File(
    p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_$safeName'),
  );
  final sink = target.openWrite();
  try {
    await sink.addStream(bytes);
  } finally {
    await sink.close();
  }
  return target.path;
}

/// Copia para a pasta do app, se ainda não estiver lá.
Future<String> persistLocalFile(String path) async {
  final dir = await _playlistDir();
  if (p.isWithin(dir.path, path)) return path;
  return persistPickedFile(p.basename(path), File(path).openRead());
}

/// Mensagem quando [error] é erro de sistema de arquivos; senão null.
String? fileSystemErrorMessage(Object error) =>
    error is FileSystemException ? error.message : null;

Stream<List<int>> gunzip(Stream<List<int>> compressed) =>
    compressed.transform(gzip.decoder);
