import 'package:flutter/foundation.dart';
import 'package:tvapp/core/player/av_player_engine.dart';
import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/exo_player_engine.dart';
import 'package:tvapp/core/player/mpv_engine.dart';
import 'package:tvapp/core/player/playback_engine.dart';

enum MediaFormat { hls, rawTs, progressive, unknown }

class EngineDescriptor {
  const EngineDescriptor({
    required this.kind,
    required this.capabilities,
    required this.isAvailable,
    required this.create,
  });

  final EngineKind kind;
  final EngineCapabilities capabilities;
  final bool isAvailable;
  final PlaybackEngine Function() create;
}

class EngineSelector {
  EngineSelector(this.descriptors, {required this.platform});

  factory EngineSelector.forPlatform(TargetPlatform platform) {
    return EngineSelector(
      <EngineDescriptor>[
        EngineDescriptor(
          kind: EngineKind.exoPlayer,
          capabilities: ExoPlayerEngine.caps,
          isAvailable: platform == TargetPlatform.android,
          create: ExoPlayerEngine.new,
        ),
        EngineDescriptor(
          kind: EngineKind.avPlayer,
          capabilities: AvPlayerEngine.caps,
          isAvailable: platform == TargetPlatform.iOS,
          create: AvPlayerEngine.new,
        ),
        EngineDescriptor(
          kind: EngineKind.mpv,
          capabilities: MpvEngine.caps,
          isAvailable: MpvEngine.isSupportedOn(platform),
          create: MpvEngine.new,
        ),
      ],
      platform: platform,
    );
  }

  final List<EngineDescriptor> descriptors;
  final TargetPlatform platform;

  static const List<String> _progressiveExtensions = <String>[
    '.mp4',
    '.mkv',
    '.mov',
    '.m4v',
    '.webm',
    '.avi',
  ];

  EngineKind get platformDefault {
    switch (platform) {
      case TargetPlatform.android:
        return EngineKind.exoPlayer;
      case TargetPlatform.iOS:
        return EngineKind.avPlayer;
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return EngineKind.mpv;
    }
  }

  bool isAvailable(EngineKind kind) {
    for (final d in descriptors) {
      if (d.kind == kind) return d.isAvailable;
    }
    return false;
  }

  static MediaFormat classify(Uri uri) {
    final path = uri.path.toLowerCase();
    final output = (uri.queryParameters['output'] ?? '').toLowerCase();
    if (path.endsWith('.m3u8') || output == 'm3u8' || output == 'hls') {
      return MediaFormat.hls;
    }
    if (path.endsWith('.ts') || output == 'ts' || output == 'mpegts') {
      return MediaFormat.rawTs;
    }
    for (final ext in _progressiveExtensions) {
      if (path.endsWith(ext)) return MediaFormat.progressive;
    }
    return MediaFormat.unknown;
  }

  /// Ordem de tentativa; o controller troca para a próxima em cada falha.
  ///
  /// Pesos: preferência do usuário (100), MPEG-TS cru numa engine que o
  /// declara (50), formato desconhecido no iOS indo para quem lê TS (20),
  /// engine padrão da plataforma (10). O desconhecido no iOS existe porque
  /// URLs de live sem extensão (padrão Xtream) costumam ser TS, que o
  /// AVPlayer não abre. Empate: ordem dos descritores.
  List<EngineDescriptor> candidatesFor(
    MediaRequest request, {
    EngineKind? preferred,
  }) {
    final format = classify(request.uri);
    final indexed = <(int, EngineDescriptor)>[];
    for (var i = 0; i < descriptors.length; i++) {
      if (descriptors[i].isAvailable) indexed.add((i, descriptors[i]));
    }

    int score(EngineDescriptor d) {
      var s = 0;
      if (preferred != null && d.kind == preferred) s += 100;
      if (format == MediaFormat.rawTs && d.capabilities.supportsRawTs) s += 50;
      if (format == MediaFormat.unknown &&
          platform == TargetPlatform.iOS &&
          d.capabilities.supportsRawTs) {
        s += 20;
      }
      if (d.kind == platformDefault) s += 10;
      return s;
    }

    indexed.sort((a, b) {
      final byScore = score(b.$2).compareTo(score(a.$2));
      return byScore != 0 ? byScore : a.$1.compareTo(b.$1);
    });
    return <EngineDescriptor>[for (final pair in indexed) pair.$2];
  }
}
