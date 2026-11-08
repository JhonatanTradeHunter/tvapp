import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/engine_selector.dart';
import 'package:tvapp/core/player/playback_engine.dart';

PlaybackEngine _unused() => throw UnimplementedError();

EngineSelector _selector(
  TargetPlatform platform, {
  required bool mpvAvailable,
}) {
  return EngineSelector(<EngineDescriptor>[
    EngineDescriptor(
      kind: EngineKind.exoPlayer,
      capabilities: const EngineCapabilities(supportsSeek: true),
      isAvailable: platform == TargetPlatform.android,
      create: _unused,
    ),
    EngineDescriptor(
      kind: EngineKind.avPlayer,
      capabilities: const EngineCapabilities(supportsSeek: true),
      isAvailable: platform == TargetPlatform.iOS,
      create: _unused,
    ),
    EngineDescriptor(
      kind: EngineKind.mpv,
      capabilities: const EngineCapabilities(supportsRawTs: true),
      isAvailable: mpvAvailable,
      create: _unused,
    ),
  ], platform: platform);
}

List<EngineKind> _kinds(List<EngineDescriptor> list) => <EngineKind>[
  for (final d in list) d.kind,
];

MediaRequest _req(String url) => MediaRequest(uri: Uri.parse(url));

void main() {
  test('classifica formato pela extensão e pelo parâmetro output', () {
    expect(
      EngineSelector.classify(Uri.parse('http://h/a/b.m3u8')),
      MediaFormat.hls,
    );
    expect(
      EngineSelector.classify(Uri.parse('http://h/a/b.ts')),
      MediaFormat.rawTs,
    );
    expect(
      EngineSelector.classify(Uri.parse('http://h/get.php?output=ts')),
      MediaFormat.rawTs,
    );
    expect(
      EngineSelector.classify(Uri.parse('http://h/f.mkv')),
      MediaFormat.progressive,
    );
    expect(
      EngineSelector.classify(Uri.parse('http://h/u/p/123')),
      MediaFormat.unknown,
    );
  });

  test('fase 1: mpv indisponível nunca entra na lista', () {
    final android = _selector(TargetPlatform.android, mpvAvailable: false);
    expect(_kinds(android.candidatesFor(_req('http://h/x.ts'))), [
      EngineKind.exoPlayer,
    ]);
    expect(android.isAvailable(EngineKind.mpv), isFalse);

    final ios = _selector(TargetPlatform.iOS, mpvAvailable: false);
    expect(_kinds(ios.candidatesFor(_req('http://h/x.m3u8'))), [
      EngineKind.avPlayer,
    ]);
  });

  test('iOS com mpv: TS cru prefere mpv, HLS prefere AVPlayer', () {
    final ios = _selector(TargetPlatform.iOS, mpvAvailable: true);
    expect(_kinds(ios.candidatesFor(_req('http://h/x.ts'))), [
      EngineKind.mpv,
      EngineKind.avPlayer,
    ]);
    expect(_kinds(ios.candidatesFor(_req('http://h/x.m3u8'))), [
      EngineKind.avPlayer,
      EngineKind.mpv,
    ]);
  });

  test('preferência do usuário vem primeiro quando disponível', () {
    final android = _selector(TargetPlatform.android, mpvAvailable: true);
    expect(
      _kinds(
        android.candidatesFor(
          _req('http://h/x.m3u8'),
          preferred: EngineKind.mpv,
        ),
      ),
      [EngineKind.mpv, EngineKind.exoPlayer],
    );
  });

  test('web: só o video_player, mesmo com navegador no Android', () {
    final web = EngineSelector.forPlatform(TargetPlatform.android, web: true);
    expect(_kinds(web.candidatesFor(_req('http://h/x.m3u8'))), [
      EngineKind.web,
    ]);
    expect(_kinds(web.candidatesFor(_req('http://h/x.ts'))), [EngineKind.web]);
    expect(web.isAvailable(EngineKind.mpv), isFalse);
    expect(web.isAvailable(EngineKind.exoPlayer), isFalse);
  });
}
