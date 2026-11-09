import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tvapp/core/data/db/app_database.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/models/channel_group.dart';
import 'package:tvapp/features/demo/demo_bootstrap.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preenche horários relativos em UTC arredondados ao minuto', () {
    final out = DemoBootstrap.fillRelativeTimes(
      '<p start="{{T-90}}" stop="{{T+30}}"/>',
      DateTime.utc(2026, 11, 8, 20, 15, 42),
    );
    expect(
      out,
      '<p start="20261108184500 +0000" stop="20261108204500 +0000"/>',
    );
  });

  test('monta fonte ativa com canais, guia relativo, filme e série', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.utc(2026, 11, 8, 20);

    await DemoBootstrap.run(
      db,
      bundle: rootBundle,
      now: now,
      assetBase: 'http://localhost/assets/assets/demo/',
    );
    await DemoBootstrap.run(
      db,
      bundle: rootBundle,
      now: now,
      assetBase: 'http://localhost/assets/assets/demo/',
    );

    final source = await db.sourceDao.watchActive().first;
    expect(source, isNotNull);
    final channels = await db.channelDao
        .watchChannels(
          profileId: 0,
          sourceId: source!.id,
          generation: 1,
          filter: const GroupFilter.all(),
          sort: LiveSort.number,
        )
        .first;
    expect(channels.map((c) => c.name), ['Demo HLS', 'Demo HLS 2', 'Demo MP4']);
    expect(
      channels.first.playbackUrl,
      'http://localhost/assets/assets/demo/clip.mp4?canal=1',
    );
    expect(channels.first.catchup, 'default');

    final programmes = await db.epgDao.programmesInRange(
      sourceId: source.id,
      generation: 1,
      channelIds: const ['demo.hls'],
      from: now.subtract(const Duration(hours: 3)),
      to: now.add(const Duration(hours: 3)),
    );
    expect(programmes, hasLength(4));
    final onAir = programmes.where(
      (p) => !p.startUtc.isAfter(now) && p.stopUtc.isAfter(now),
    );
    expect(onAir.single.title, 'No ar agora');
    expect(programmes.first.stopUtc.isBefore(now), isTrue);

    expect(await db.vodDao.countVod(source.id, 1), 1);
  });
}
