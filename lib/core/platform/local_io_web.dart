import 'package:tvapp/core/models/playlist_source.dart';

const bool localFilesSupported = false;

Future<(Stream<List<int>>, int)> openLocalFile(String path) async {
  throw const SourceException(SourceError.notFound, detail: 'web');
}

Future<(int, List<int>)?> probeLocalFile(String path, int maxBytes) async =>
    null;

Future<String> persistPickedFile(String name, Stream<List<int>> bytes) async {
  throw const SourceException(SourceError.notFound, detail: 'web');
}

Future<String> persistLocalFile(String path) async {
  throw const SourceException(SourceError.notFound, detail: 'web');
}

String? fileSystemErrorMessage(Object error) => null;

/// O navegador já descompacta respostas com Content-Encoding: gzip; um
/// arquivo .xml.gz servido cru não é suportado na web.
Stream<List<int>> gunzip(Stream<List<int>> compressed) =>
    Stream<List<int>>.error(
      const SourceException(SourceError.invalidContent, detail: 'gzip-web'),
    );
