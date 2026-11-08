// Acesso a arquivos locais e gzip. No nativo usa dart:io; na web não há
// sistema de arquivos e as funções falham com SourceException.
export 'local_io_native.dart' if (dart.library.js_interop) 'local_io_web.dart';
