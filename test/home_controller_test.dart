import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/features/channels/data/playlist_repository.dart';
import 'package:nontontv_flutter/features/channels/domain/playlist_result.dart';
import 'package:nontontv_flutter/features/channels/domain/playlist_source.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_controller.dart';

import 'support/fakes.dart';

void main() {
  late FakeRepository repository;
  late FakeStorage storage;
  late HomeController controller;
  late Directory directory;

  setUp(() async {
    repository = FakeRepository();
    storage = FakeStorage();
    directory = await Directory.systemTemp.createTemp('nontontv_test_');
    controller = HomeController(repository: repository, storage: storage,
      filesDirectory: () async => directory.path);
    await controller.initialize();
  });
  tearDown(() async { controller.dispose(); await directory.delete(recursive: true); });

  test('failed URL addition preserves selected source and persisted sources', () async {
    repository.failure = const PlaylistException('offline');
    await expectLater(controller.addUrlSource(name: 'Bad', url: 'https://example.com/bad'), throwsA(isA<PlaylistException>()));
    expect(controller.sources, hasLength(1));
    expect(storage.savedSources, hasLength(1));
    expect(controller.selectedSource?.id, firstSource.id);
    expect(controller.channels.single.name, 'News');
    expect(controller.loading, isFalse);
  });

  test('successful add is selected and duplicate URL is not added twice', () async {
    await controller.addUrlSource(name: 'Second', url: 'https://example.com/second');
    expect(controller.sources, hasLength(2));
    expect(controller.channels.single.name, 'Sport');
    final id = controller.selectedSource!.id;
    await controller.addUrlSource(name: 'Again', url: ' https://example.com/second ');
    expect(controller.sources, hasLength(2));
    expect(controller.selectedSource?.id, id);
  });

  test('storage failure does not publish the newly loaded playlist', () async {
    storage.failWrites = true;
    await expectLater(controller.addUrlSource(name: 'Second', url: 'https://example.com/second'), throwsStateError);
    expect(controller.sources, hasLength(1));
    expect(controller.channels.single.name, 'News');
  });

  test('failed refresh keeps current channel list', () async {
    final before = controller.channels;
    repository.failure = const PlaylistException('offline');
    await controller.reload();
    expect(identical(controller.channels, before), isTrue);
    expect(controller.error, 'offline');
  });

  test('source switching failure keeps previous source and content paired', () async {
    await controller.addUrlSource(name: 'Second', url: 'https://example.com/second');
    repository.failure = const PlaylistException('offline');
    await controller.selectSource(firstSource);
    expect(controller.selectedSource?.name, 'Second');
    expect(controller.channels.single.name, 'Sport');
  });

  test('simultaneous imports cannot race or duplicate sources', () async {
    repository.pending = Completer<PlaylistResult>();
    final first = controller.addUrlSource(name: 'Second', url: 'https://example.com/second');
    await expectLater(controller.addUrlSource(name: 'Third', url: 'https://example.com/third'), throwsA(isA<PlaylistException>()));
    repository.pending!.complete(sampleResult('Sport'));
    await first;
    expect(controller.sources, hasLength(2));
  });

  test('invalid local file leaves no source and no copied file', () async {
    await expectLater(controller.importLocalSource(name: 'Bad', fileName: 'bad.m3u', bytes: utf8.encode('garbage')),
      throwsA(isA<PlaylistException>()));
    expect(controller.sources, hasLength(1));
    expect(await directory.list(recursive: true).toList(), isEmpty);
  });

  test('local file is copied and can reload after import', () async {
    await controller.importLocalSource(name: 'Local', fileName: 'local.m3u',
      bytes: utf8.encode('#EXTINF:-1,Local News\nhttps://example.com/live'));
    expect(controller.selectedSource?.type, PlaylistSourceType.localFile);
    expect(await File(controller.selectedSource!.location).exists(), isTrue);
    await controller.reload();
    expect(controller.channels.single.name, 'Local News');
  });

  test('failed local persistence cleans up copied file', () async {
    storage.failWrites = true;
    await expectLater(controller.importLocalSource(name: 'Local', fileName: 'local.m3u',
      bytes: utf8.encode('https://example.com/live')), throwsStateError);
    expect(await directory.list(recursive: true).where((e) => e is File).toList(), isEmpty);
    expect(controller.sources, hasLength(1));
  });

  test('groups are cached until playlist content changes', () async {
    final groups = controller.groupedChannels;
    await controller.toggleFavorite(controller.channels.single);
    expect(identical(groups, controller.groupedChannels), isTrue);
    expect(controller.currentFavorites.single.name, 'News');
  });
}
