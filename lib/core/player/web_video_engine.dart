import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/video_player_engine_base.dart';

/// `video_player` na web (elemento <video> do navegador). MP4 em qualquer
/// navegador; HLS só onde o navegador toca nativamente (Safari).
class WebVideoEngine extends VideoPlayerEngineBase {
  static const EngineCapabilities caps = EngineCapabilities(supportsSeek: true);

  @override
  EngineKind get kind => EngineKind.web;

  @override
  EngineCapabilities get capabilities => caps;
}
