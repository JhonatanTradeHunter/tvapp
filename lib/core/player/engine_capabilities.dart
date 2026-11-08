/// A UI degrada pelas flags, nunca pelo tipo concreto da engine.
class EngineCapabilities {
  const EngineCapabilities({
    this.supportsSeek = false,
    this.supportsTrackSelection = false,
    this.supportsAudioDelay = false,
    this.supportsRawTs = false,
    this.supportsBufferTuning = false,
  });

  static const EngineCapabilities none = EngineCapabilities();

  final bool supportsSeek;
  final bool supportsTrackSelection;
  final bool supportsAudioDelay;
  final bool supportsRawTs;

  /// A engine aceita timeout de rede e tamanho de cache nativos.
  /// Sem isso, o limite de 8s é aplicado por fora (`Future.timeout`).
  final bool supportsBufferTuning;
}
