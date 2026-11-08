import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/video_player_engine_base.dart';

/// AVPlayer via `video_player` no iOS. Reproduz HLS; MPEG-TS cru fica com mpv.
class AvPlayerEngine extends VideoPlayerEngineBase {
  static const EngineCapabilities caps = EngineCapabilities(supportsSeek: true);

  @override
  EngineKind get kind => EngineKind.avPlayer;

  @override
  EngineCapabilities get capabilities => caps;
}
