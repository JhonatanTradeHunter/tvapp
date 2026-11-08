import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/daos/position_dao.dart';
import 'package:tvapp/features/vod/vod_controller.dart';

void main() {
  const hour = Duration(hours: 1);

  test('posição curta demais não é guardada', () {
    expect(
      PositionDao.worthKeeping(const Duration(seconds: 29), hour),
      isFalse,
    );
    expect(PositionDao.worthKeeping(const Duration(seconds: 30), hour), isTrue);
  });

  test('acima de 95% conta como assistido', () {
    expect(PositionDao.isFinished(const Duration(minutes: 57), hour), isTrue);
    expect(PositionDao.isFinished(const Duration(minutes: 56), hour), isFalse);
    expect(
      PositionDao.worthKeeping(const Duration(minutes: 58), hour),
      isFalse,
    );
  });

  test('sem duração conhecida nunca conta como assistido', () {
    expect(PositionDao.isFinished(hour, Duration.zero), isFalse);
  });

  test('filme e episódio com o mesmo id têm chaves e ids distintos', () {
    expect(vodItemKey(VodTab.movies, 5), 'movie|5');
    expect(vodItemKey(VodTab.series, 5), 'episode|5');
    final url = Uri.parse('http://h/x.mp4');
    final movie = playableItem(
      kind: VodTab.movies,
      id: 5,
      sourceId: 1,
      title: 'Filme',
      url: url,
    );
    final episode = playableItem(
      kind: VodTab.series,
      id: 5,
      sourceId: 1,
      title: 'Episódio',
      url: url,
    );
    expect(movie.id, isNot(episode.id));
    expect(movie.id, isNegative);
    expect(episode.id, isNegative);
  });
}
