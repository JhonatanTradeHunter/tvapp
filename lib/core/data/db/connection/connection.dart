// Abre o banco conforme a plataforma, sem levar `dart:ffi` para a web.
export 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';
