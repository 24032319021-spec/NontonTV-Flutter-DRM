import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../../../core/platform/android_tv_platform.dart';
import '../../../storage/app_storage.dart';
import '../data/playlist_repository.dart';
import '../domain/channel.dart';
import '../domain/playlist_result.dart';
import '../domain/playlist_source.dart';

class HomeController extends ChangeNotifier {
  HomeController({PlaylistRepository? repository, AppStorage? storage,
    Future<String?> Function()? filesDirectory})
      : _repository = repository ?? PlaylistRepository(),
        _storage = storage ?? AppStorage(),
        _filesDirectory = filesDirectory ?? AndroidTvPlatform.getApplicationFilesDirectory;

  final PlaylistRepository _repository;
  final AppStorage _storage;
  final Future<String?> Function() _filesDirectory;
  final List<PlaylistSource> _sources = [];
  final List<TvChannel> _favorites = [];
  final Set<String> _favoriteIds = {};
  List<TvChannel> _channels = const [];
  Map<String, List<TvChannel>> _groups = const {};
  List<String> _groupNames = const [];
  Set<String> _channelIds = {};
  PlaylistSource? _selectedSource;
  PlaylistResult? _importResult;
  bool _loading = false;
  bool _initialized = false;
  bool _disposed = false;
  bool _autoResume = true;
  bool _optimizePrebuffer = true;
  String _userAgent = '';
  String? _error;
  String? _lastChannelId;

  List<PlaylistSource> get sources => UnmodifiableListView(_sources);
  List<TvChannel> get channels => _channels;
  List<TvChannel> get favorites => UnmodifiableListView(_favorites);
  List<TvChannel> get currentFavorites => _channels
      .where((channel) => _favoriteIds.contains(channel.id)).toList(growable: false);
  int get currentFavoriteCount => _favoriteIds.where(_channelIds.contains).length;
  Map<String, List<TvChannel>> get groupedChannels => _groups;
  List<String> get groupNames => _groupNames;
  PlaylistSource? get selectedSource => _selectedSource;
  PlaylistResult? get importResult => _importResult;
  bool get loading => _loading;
  bool get initialized => _initialized;
  bool get autoResume => _autoResume;
  bool get optimizePrebuffer => _optimizePrebuffer;
  String get userAgent => _userAgent;
  String? get error => _error;

  void _notify() { if (!_disposed) notifyListeners(); }

  void _setChannels(PlaylistResult result) {
    _importResult = result;
    _channels = result.channels;
    _channelIds = _channels.map((c) => c.id).toSet();
    final grouped = <String, List<TvChannel>>{};
    for (final channel in _channels) {
      grouped.putIfAbsent(channel.group, () => []).add(channel);
    }
    _groups = Map.unmodifiable(grouped.map((key, value) =>
        MapEntry(key, List<TvChannel>.unmodifiable(value))));
    _groupNames = List.unmodifiable(grouped.keys.toList()..sort());
  }

  Future<void> initialize() async {
    if (_initialized || _loading || _disposed) return;
    _loading = true;
    _notify();
    try {
      _favorites.addAll(await _storage.readFavorites());
      _favoriteIds.addAll(_favorites.map((e) => e.id));
      _sources.addAll(await _storage.readSources());
      _autoResume = await _storage.readAutoResume();
      _optimizePrebuffer = await _storage.readOptimizePrebuffer();
      _userAgent = await _storage.readUserAgent();
      _lastChannelId = await _storage.readLastChannelId();
      final lastSourceId = await _storage.readLastSourceId();
      if (_sources.isEmpty) {
        _sources.add(const PlaylistSource(
          id: 'iptv-org-id', name: 'Indonesia · IPTV.org',
          location: 'https://iptv-org.github.io/iptv/countries/id.m3u',
          type: PlaylistSourceType.url,
        ));
        await _storage.writeSources(_sources);
      }
      if (_disposed) return;
      _selectedSource = _sources.where((e) => e.id == lastSourceId).firstOrNull ?? _sources.first;
      final result = await _readSource(_selectedSource!);
      if (!_disposed) _setChannels(result);
    } catch (e) {
      _error = messageFor(e);
    } finally {
      _loading = false;
      _initialized = true;
      _notify();
    }
  }

  static String messageFor(Object error) => error is PlaylistException
      ? error.message
      : error is FileSystemException
          ? 'File playlist tidak dapat dibaca. Pilih kembali file yang tersedia.'
          : 'Operasi gagal. Periksa koneksi dan ruang penyimpanan, lalu coba lagi.';

  void _begin() {
    if (_disposed || _loading) {
      throw const PlaylistException('Tunggu proses playlist yang sedang berjalan.');
    }
    _loading = true;
    _error = null;
    _notify();
  }

  void _end() { _loading = false; _notify(); }

  Future<PlaylistResult> _readSource(PlaylistSource source) async {
    if (source.type == PlaylistSourceType.url) {
      return _repository.loadUrlDetailed(source.location);
    }
    final file = File(source.location);
    if (await file.length() > PlaylistRepository.maxBytes) {
      throw const PlaylistException('Ukuran playlist melebihi batas 20 MB.');
    }
    return _repository.loadBytesDetailed(await file.readAsBytes(), hint: source.location);
  }

  Future<void> _rememberSource(String id) async {
    try {
      await _storage.writeLastSourceId(id);
    } catch (_) {
      _error = 'Playlist siap, tetapi pilihan terakhir belum berhasil disimpan.';
    }
  }

  Future<void> addUrlSource({required String name, required String url}) async {
    final normalized = url.trim();
    final uri = PlaylistRepository.validateUrl(normalized);
    _begin();
    try {
      final existing = _sources.where((s) =>
          s.type == PlaylistSourceType.url && s.location == normalized).firstOrNull;
      final result = await _repository.loadUrlDetailed(normalized);
      if (_disposed) return;
      final source = existing ?? PlaylistSource(
        id: 'url-${DateTime.now().microsecondsSinceEpoch}',
        name: name.trim().isEmpty ? uri.host : name.trim(),
        location: normalized, type: PlaylistSourceType.url,
      );
      // Validation comes first; a failed download never adds a broken source.
      if (existing == null) {
        await _storage.writeSources([..._sources, source]);
        _sources.add(source);
      }
      _selectedSource = source;
      _setChannels(result);
      await _rememberSource(source.id);
    } catch (e) {
      _error = messageFor(e);
      rethrow;
    } finally { _end(); }
  }

  Future<void> importLocalSource({required String name, required String fileName,
      required List<int> bytes}) async {
    _begin();
    File? target;
    var committed = false;
    try {
      final result = await _repository.loadBytesDetailed(bytes, hint: fileName);
      if (_disposed) return;
      final basePath = await _filesDirectory();
      if (basePath == null || basePath.isEmpty) {
        throw const PlaylistException('Folder penyimpanan aplikasi tidak tersedia.');
      }
      final directory = Directory('$basePath${Platform.pathSeparator}playlists');
      await directory.create(recursive: true);
      final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final id = DateTime.now().microsecondsSinceEpoch;
      target = File('${directory.path}${Platform.pathSeparator}${id}_$safeName');
      await target.writeAsBytes(bytes, flush: true);
      if (_disposed) return;
      final source = PlaylistSource(
        id: 'file-$id', name: name.trim().isEmpty ? fileName : name.trim(),
        location: target.path, type: PlaylistSourceType.localFile,
      );
      await _storage.writeSources([..._sources, source]);
      committed = true;
      _sources.add(source);
      _selectedSource = source;
      _setChannels(result);
      await _rememberSource(source.id);
    } catch (e) {
      _error = messageFor(e);
      rethrow;
    } finally {
      if (!committed && target != null) {
        try { await target.delete(); } on FileSystemException { /* Best effort. */ }
      }
      _end();
    }
  }

  Future<void> selectSource(PlaylistSource source) async {
    if (_loading || _disposed || !_sources.any((s) => s.id == source.id)) return;
    _begin();
    try {
      final result = await _readSource(source);
      if (_disposed) return;
      _selectedSource = source;
      _setChannels(result);
      await _rememberSource(source.id);
    } catch (e) {
      // Keep the previous source and its channels together on failure.
      _error = messageFor(e);
    } finally { _end(); }
  }

  Future<void> reload() async {
    final source = _selectedSource;
    if (source != null) await selectSource(source);
  }

  bool isFavorite(TvChannel channel) => _favoriteIds.contains(channel.id);

  Future<void> toggleFavorite(TvChannel channel) async {
    final next = List<TvChannel>.of(_favorites);
    if (isFavorite(channel)) {
      next.removeWhere((e) => e.id == channel.id);
    } else { next.add(channel); }
    try {
      // Update immediately; each storage call receives its own encoded snapshot.
      _favorites..clear()..addAll(next);
      _favoriteIds..clear()..addAll(next.map((e) => e.id));
      _notify();
      await _storage.writeFavorites(next);
    } catch (e) {
      _error = messageFor(e);
      _notify();
    }
  }

  Future<void> rememberChannel(TvChannel channel) async {
    _lastChannelId = channel.id;
    try { await _storage.writeLastChannelId(channel.id); } catch (_) {
      // A preference failure must never prevent opening the existing player.
    }
  }

  TvChannel? get resumableChannel => !_autoResume || _lastChannelId == null
      ? null : _channels.where((e) => e.id == _lastChannelId).firstOrNull;

  Future<void> setAutoResume(bool value) async {
    _autoResume = value;
    await _storage.writeAutoResume(value);
    _notify();
  }
  Future<void> setOptimizePrebuffer(bool value) async {
    _optimizePrebuffer = value;
    await _storage.writeOptimizePrebuffer(value);
    _notify();
  }
  Future<void> setUserAgent(String value) async {
    _userAgent = value.trim();
    await _storage.writeUserAgent(_userAgent);
    _notify();
  }

  Future<void> removeSource(PlaylistSource source) async {
    if (_loading || _disposed || _sources.length <= 1 ||
        !_sources.any((s) => s.id == source.id)) {
      return;
    }
    _begin();
    try {
      final remaining = _sources.where((e) => e.id != source.id).toList();
      // Load a replacement before removing the currently displayed source.
      final replacing = _selectedSource?.id == source.id;
      final result = replacing ? await _readSource(remaining.first) : null;
      if (_disposed) return;
      await _storage.writeSources(remaining);
      _sources..clear()..addAll(remaining);
      if (result != null) {
        _selectedSource = remaining.first;
        _setChannels(result);
        await _rememberSource(remaining.first.id);
      }
      if (source.type == PlaylistSourceType.localFile) {
        try { await File(source.location).delete(); } on FileSystemException { /* Best effort. */ }
      }
    } catch (e) { _error = messageFor(e); }
    finally { _end(); }
  }

  @override
  void dispose() {
    _disposed = true;
    _repository.dispose();
    super.dispose();
  }
}
