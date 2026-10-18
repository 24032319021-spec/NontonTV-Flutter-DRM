import 'dart:async';

import 'package:nontontv_flutter/features/channels/data/playlist_repository.dart';
import 'package:nontontv_flutter/features/channels/domain/channel.dart';
import 'package:nontontv_flutter/features/channels/domain/playlist_result.dart';
import 'package:nontontv_flutter/features/channels/domain/playlist_source.dart';
import 'package:nontontv_flutter/storage/app_storage.dart';

const firstSource = PlaylistSource(id: 'first', name: 'First',
  location: 'https://example.com/first.m3u', type: PlaylistSourceType.url);

PlaylistResult sampleResult([String name = 'News']) => PlaylistResult(channels: [
  TvChannel(id: name, name: name, url: 'https://example.com/live', group: 'General'),
]);

class FakeRepository extends PlaylistRepository {
  Object? failure;
  Completer<PlaylistResult>? pending;
  int calls = 0;

  @override
  Future<PlaylistResult> loadUrlDetailed(String url) async {
    calls++;
    if (failure != null) throw failure!;
    if (pending != null) return pending!.future;
    return sampleResult(url.contains('second') ? 'Sport' : 'News');
  }
}

class FakeStorage extends AppStorage {
  List<PlaylistSource> savedSources = [firstSource];
  bool failWrites = false;
  String? lastSource = firstSource.id;

  @override
  Future<List<PlaylistSource>> readSources() async => List.of(savedSources);
  @override
  Future<List<TvChannel>> readFavorites() async => [];
  @override
  Future<bool> readAutoResume() async => false;
  @override
  Future<bool> readOptimizePrebuffer() async => true;
  @override
  Future<String> readUserAgent() async => '';
  @override
  Future<String?> readLastChannelId() async => null;
  @override
  Future<String?> readLastSourceId() async => lastSource;
  @override
  Future<void> writeLastSourceId(String id) async { lastSource = id; }
  @override
  Future<void> writeSources(List<PlaylistSource> sources) async {
    if (failWrites) throw StateError('disk full');
    savedSources = List.of(sources);
  }
  @override
  Future<void> writeUserAgent(String value) async {}
  @override
  Future<void> writeFavorites(List<TvChannel> channels) async {}
}
