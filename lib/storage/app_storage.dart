import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/channels/domain/channel.dart';
import '../features/channels/domain/playlist_source.dart';

class AppStorage {
  static const _favoritesKey = 'favorites.v1';
  static const _sourcesKey = 'playlist_sources.v1';
  static const _lastChannelKey = 'last_channel.v1';
  static const _lastSourceKey = 'last_source.v1';
  static const _autoResumeKey = 'auto_resume.v1';
  static const _optimizePrebufferKey = 'optimize_prebuffer.v1';
  static const _userAgentKey = 'user_agent.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<TvChannel>> readFavorites() async {
    final raw = (await _prefs).getString(_favoritesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => TvChannel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> writeFavorites(List<TvChannel> channels) async {
    await (await _prefs).setString(
      _favoritesKey,
      jsonEncode(channels.map((e) => e.toJson()).toList()),
    );
  }

  Future<List<PlaylistSource>> readSources() async {
    final raw = (await _prefs).getString(_sourcesKey);
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => PlaylistSource.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<void> writeSources(List<PlaylistSource> sources) async {
    final saved = await (await _prefs).setString(
      _sourcesKey,
      jsonEncode(sources.map((e) => e.toJson()).toList()),
    );
    if (!saved) throw StateError('Playlist tidak berhasil disimpan.');
  }

  Future<String?> readLastChannelId() async => (await _prefs).getString(_lastChannelKey);
  Future<void> writeLastChannelId(String id) async => (await _prefs).setString(_lastChannelKey, id);

  Future<String?> readLastSourceId() async => (await _prefs).getString(_lastSourceKey);
  Future<void> writeLastSourceId(String id) async => (await _prefs).setString(_lastSourceKey, id);

  Future<bool> readAutoResume() async => (await _prefs).getBool(_autoResumeKey) ?? true;
  Future<void> writeAutoResume(bool value) async => (await _prefs).setBool(_autoResumeKey, value);

  Future<bool> readOptimizePrebuffer() async =>
      (await _prefs).getBool(_optimizePrebufferKey) ?? true;
  Future<void> writeOptimizePrebuffer(bool value) async =>
      (await _prefs).setBool(_optimizePrebufferKey, value);

  Future<String> readUserAgent() async =>
      (await _prefs).getString(_userAgentKey) ?? '';
  Future<void> writeUserAgent(String value) async =>
      (await _prefs).setString(_userAgentKey, value.trim());
}
