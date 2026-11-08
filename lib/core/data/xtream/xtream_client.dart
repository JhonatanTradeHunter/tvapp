import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:tvapp/core/data/source/playlist_loader.dart';
import 'package:tvapp/core/data/xtream/json_read.dart';
import 'package:tvapp/core/data/xtream/xtream_models.dart';
import 'package:tvapp/core/models/playlist_source.dart';

/// Cliente da API de-facto do Xtream Codes (`player_api.php`). Só leitura.
/// Respostas grandes (listas com dezenas de milhares de itens) são
/// decodificadas e mapeadas dentro de um isolate.
class XtreamClient {
  XtreamClient(
    this.credentials, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 20),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final XtreamCredentials credentials;
  final Duration timeout;
  final http.Client Function() _clientFactory;

  Uri apiUri([String? action, Map<String, String> extra = const {}]) {
    final base = credentials.baseUri;
    return base.replace(
      path: '${base.path}/player_api.php',
      queryParameters: <String, String>{
        'username': credentials.username,
        'password': credentials.password,
        'action': ?action,
        ...extra,
      },
    );
  }

  Uri liveUrl(int streamId, {String extension = 'm3u8'}) =>
      _media('live', streamId, extension);

  Uri movieUrl(int streamId, {String? extension}) =>
      _media('movie', streamId, extension ?? 'mp4');

  Uri episodeUrl(int episodeId, {String? extension}) =>
      _media('series', episodeId, extension ?? 'mp4');

  Uri _media(String kind, int id, String extension) {
    final base = credentials.baseUri;
    return base.replace(
      pathSegments: <String>[
        ...base.pathSegments.where((s) => s.isNotEmpty),
        kind,
        credentials.username,
        credentials.password,
        '$id.$extension',
      ],
    );
  }

  /// Sem `action` o painel devolve `user_info` e `server_info`.
  /// `auth` diferente de 1 vira erro de credencial.
  Future<XtreamAccount> authenticate() async {
    final account = await _fetch(apiUri(), XtreamAccount.fromJson);
    if (!account.authenticated) {
      throw const SourceException(SourceError.credentials, detail: 'auth=0');
    }
    return account;
  }

  Future<List<XtreamCategory>> liveCategories() =>
      _fetch(apiUri('get_live_categories'), _parseCategories);

  Future<List<XtreamCategory>> vodCategories() =>
      _fetch(apiUri('get_vod_categories'), _parseCategories);

  Future<List<XtreamCategory>> seriesCategories() =>
      _fetch(apiUri('get_series_categories'), _parseCategories);

  Future<List<XtreamLiveStream>> liveStreams() =>
      _fetch(apiUri('get_live_streams'), _parseLive);

  Future<List<XtreamVodStream>> vodStreams() =>
      _fetch(apiUri('get_vod_streams'), _parseVod);

  Future<List<XtreamSeries>> series() =>
      _fetch(apiUri('get_series'), _parseSeries);

  Future<XtreamSeriesInfo> seriesInfo(int seriesId) => _fetch(
    apiUri('get_series_info', <String, String>{'series_id': '$seriesId'}),
    XtreamSeriesInfo.fromJson,
  );

  Future<XtreamVodInfo> vodInfo(int vodId) => _fetch(
    apiUri('get_vod_info', <String, String>{'vod_id': '$vodId'}),
    XtreamVodInfo.fromJson,
  );

  Future<T> _fetch<T>(Uri uri, T Function(Object? json) parse) async {
    final client = _clientFactory();
    try {
      final request = http.Request('GET', uri)
        ..headers.addAll(PlaylistLoader.defaultHeaders);
      final http.StreamedResponse response;
      try {
        response = await client.send(request).timeout(timeout);
      } on TimeoutException {
        throw const SourceException(SourceError.timeout);
      } catch (error) {
        throw SourceException(SourceError.network, detail: '$error');
      }
      final failure = PlaylistLoader.classifyResponse(
        response.statusCode,
        response.headers['content-type'],
        credentialsMode: true,
      );
      if (failure != null) throw failure;
      final Uint8List bytes;
      try {
        bytes = await response.stream.toBytes().timeout(timeout * 3);
      } on TimeoutException {
        throw const SourceException(SourceError.timeout);
      }
      return await decodeInIsolate(bytes, parse);
    } finally {
      client.close();
    }
  }

  /// Corpo vazio ou que não é JSON (HTML de login, "Access denied") vira
  /// erro de credencial: é o que o painel faz com usuário ou senha errados.
  static Future<T> decodeInIsolate<T>(
    Uint8List bytes,
    T Function(Object? json) parse,
  ) async {
    try {
      return await compute(_decodeWith<T>, (bytes, parse));
    } on FormatException catch (e) {
      throw SourceException(SourceError.credentials, detail: e.message);
    }
  }

  static T _decodeWith<T>((Uint8List, T Function(Object? json)) args) =>
      args.$2(_decode(args.$1));

  static Object? _decode(Uint8List bytes) {
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isEmpty) throw const FormatException('corpo vazio');
    return jsonDecode(text);
  }

  static List<XtreamCategory> _parseCategories(Object? json) =>
      <XtreamCategory>[
        for (final item in JsonRead.list(json)) ?XtreamCategory.fromJson(item),
      ];

  static List<XtreamLiveStream> _parseLive(Object? json) => <XtreamLiveStream>[
    for (final item in JsonRead.list(json)) ?XtreamLiveStream.fromJson(item),
  ];

  static List<XtreamVodStream> _parseVod(Object? json) => <XtreamVodStream>[
    for (final item in JsonRead.list(json)) ?XtreamVodStream.fromJson(item),
  ];

  static List<XtreamSeries> _parseSeries(Object? json) => <XtreamSeries>[
    for (final item in JsonRead.list(json)) ?XtreamSeries.fromJson(item),
  ];
}
