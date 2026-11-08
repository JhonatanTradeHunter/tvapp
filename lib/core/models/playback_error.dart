enum PlaybackError {
  Rede,
  Http4xx,
  Http5xx,
  Codec,
  FonteInvalida,
  Desconhecido,
}

class PlaybackException implements Exception {
  const PlaybackException(this.error, [this.detail]);

  final PlaybackError error;
  final String? detail;

  @override
  String toString() =>
      'PlaybackException(${error.name}${detail == null ? '' : ': $detail'})';
}
