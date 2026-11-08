import 'package:tvapp/core/player/engine_capabilities.dart';
import 'package:tvapp/core/player/playback_engine.dart';
import 'package:tvapp/core/player/video_player_engine_base.dart';

/// ExoPlayer via `video_player` no Android.
class ExoPlayerEngine extends VideoPlayerEngineBase {
  static const EngineCapabilities caps = EngineCapabilities(supportsSeek: true);

  @override
  EngineKind get kind => EngineKind.exoPlayer;

  @override
  EngineCapabilities get capabilities => caps;
}
