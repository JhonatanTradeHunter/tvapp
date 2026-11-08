import 'package:shared_preferences/shared_preferences.dart';
import 'package:tvapp/core/models/channel.dart';
import 'package:tvapp/core/player/playback_engine.dart';

class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const String _kLiveSort = 'live.sort';
  static const String _kLastChannelKey = 'live.lastChannelKey';
  static const String _kPreferredEngine = 'player.preferredEngine';
  static const String _kActiveProfile = 'profiles.active';

  LiveSort get liveSort {
    final value = _prefs.getString(_kLiveSort);
    for (final sort in LiveSort.values) {
      if (sort.name == value) return sort;
    }
    return LiveSort.number;
  }

  Future<void> setLiveSort(LiveSort sort) =>
      _prefs.setString(_kLiveSort, sort.name);

  String? get lastChannelKey => _prefs.getString(_kLastChannelKey);

  Future<void> setLastChannelKey(String key) =>
      _prefs.setString(_kLastChannelKey, key);

  int? get activeProfileId => _prefs.getInt(_kActiveProfile);

  Future<void> setActiveProfileId(int? id) => id == null
      ? _prefs.remove(_kActiveProfile)
      : _prefs.setInt(_kActiveProfile, id);

  EngineKind? get preferredEngine {
    final value = _prefs.getString(_kPreferredEngine);
    for (final kind in EngineKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }

  Future<void> setPreferredEngine(EngineKind? kind) => kind == null
      ? _prefs.remove(_kPreferredEngine)
      : _prefs.setString(_kPreferredEngine, kind.name);
}
