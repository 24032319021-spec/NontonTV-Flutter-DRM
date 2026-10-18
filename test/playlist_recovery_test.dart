import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nontontv_flutter/features/channels/data/m3u_parser.dart';
import 'package:nontontv_flutter/features/channels/data/playlist_repository.dart';
import 'package:nontontv_flutter/features/channels/domain/channel.dart';

void main() {
  test('BOM, CRLF, mixed-case tags and alternate quotes', () {
    final channels = M3uParser().parse("\uFEFF#extm3u\r\n#extinf:-1 tvg-id='one' group-title=News,One\r\nhttps://example.com/live\r\n");
    expect(channels.single.name, 'One');
    expect(channels.single.group, 'News');
    expect(channels.single.tvgId, 'one');
  });

  test('commas inside attributes do not truncate a channel name', () {
    final result = M3uParser().parse('#EXTINF:-1 group-title="News, Local",One, HD\nhttps://example.com/live');
    expect(result.single.group, 'News, Local');
    expect(result.single.name, 'One, HD');
  });

  test('missing comma and EXTINF recover names without losing URLs', () {
    final result = M3uParser().parseDetailed('#EXTINF:-1 tvg-name="Recovered"\nhttps://example.com/one\nhttps://example.com/two');
    expect(result.channels, hasLength(2));
    expect(result.channels.first.name, 'Recovered');
    expect(result.recovered, 2);
  });

  test('bad percent escapes in headers do not abort the whole playlist', () {
    // Invalid/truncated escapes throw ArgumentError; invalid UTF-8 can throw
    // FormatException. Neither may discard this or the following channel.
    for (final value in ['Bad%ZZ', 'Bad%', 'Bad%2', 'Bad%FF', 'Café']) {
      final result = M3uParser().parse('#EXTINF:-1,One\nhttps://example.com/a|User-Agent=$value&Referer=https%3A%2F%2Fexample.com%2F\n#EXTINF:-1,Two\nhttps://example.com/b');
      expect(result, hasLength(2), reason: value);
      expect(result.first.userAgent, value, reason: value);
      expect(result.first.referrer, 'https://example.com/', reason: value);
      expect(result.last.name, 'Two', reason: value);
    }
  });

  test('valid header escapes decode once and preserve literal plus and percent', () {
    final channel = M3uParser().parse(
      'https://example.com/live|User-Agent=Client%2B1%20token%252F+tail',
    ).single;
    expect(channel.userAgent, 'Client+1 token%2F+tail');
  });

  test('orphan EXTINF cannot leak DRM or headers to the next channel', () {
    final result = M3uParser().parseDetailed('''
#EXTINF:-1,Orphan
#KODIPROP:inputstream.adaptive.license_type=widevine
#KODIPROP:inputstream.adaptive.license_key=https://license.example.com/
#EXTVLCOPT:http-user-agent=SecretAgent
#EXTINF:-1,Public
https://example.com/public
''');
    expect(result.channels.single.drmKey, isNull);
    expect(result.channels.single.userAgent, isNull);
    expect(result.skipped, 1);
  });

  test('invalid entry is skipped without losing later valid entries', () {
    final result = M3uParser().parseDetailed('#EXTINF:-1,Bad\nnot a URL\n#EXTINF:-1,Good\nhttps://example.com/good\n#EXTINF:-1,Orphan');
    expect(result.channels.single.name, 'Good');
    expect(result.skipped, 2);
  });

  test('exact duplicates collapse but distinct groups and DRM remain', () {
    final result = M3uParser().parseDetailed('''
#EXTINF:-1 group-title="A",One
https://example.com/live
#EXTINF:-1 group-title="A",One
https://example.com/live
#EXTINF:-1 group-title="B",One
https://example.com/live
#EXTINF:-1 group-title="A",One
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=0011:2233
https://example.com/live
''');
    expect(result.channels, hasLength(3));
    expect(result.duplicates, 1);
  });

  test('relative URL resolution leaves absolute signed URL untouched', () {
    const signed = 'https://cdn.example.com/live?token=A%2Fb%2Bq&x=1';
    final result = M3uParser().parse('#EXTINF:-1,One\n../live/one.m3u8\n#EXTINF:-1,Two\n$signed',
      baseUri: Uri.parse('https://example.com/catalog/list.m3u'));
    expect(result[0].url, 'https://example.com/live/one.m3u8');
    expect(result[1].url, signed);
  });

  test('EXTHTTP headers survive favorites serialization and inline override', () {
    final channel = M3uParser().parse('''
#EXTINF:-1,One
#EXTHTTP:{"User-Agent":"Old","Referer":"https://origin.example.com/","Origin":"https://origin.example.com","Cookie":"session=test"}
https://example.com/live|User-Agent=New
''').single;
    expect(channel.httpHeaders['User-Agent'], 'New');
    expect(channel.httpHeaders['Referer'], 'https://origin.example.com/');
    expect(channel.httpHeaders['origin'], 'https://origin.example.com');
    expect(channel.httpHeaders['cookie'], 'session=test');
    expect(TvChannel.fromJson(channel.toJson()).httpHeaders, channel.httpHeaders);
    expect(channel.copyWith(group: 'Other').httpHeaders, channel.httpHeaders);
  });

  test('header line injection is ignored', () {
    final channel = M3uParser().parse('https://example.com/live|User-Agent=ok%0D%0AX-Evil%3Ayes').single;
    expect(channel.httpHeaders, isEmpty);
  });

  test('playlist content takes priority over extension', () {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    expect(repo.parse('[{"name":"One","url":"https://example.com/live"}]', hint: 'wrong.m3u').single.name, 'One');
    expect(repo.parse('#EXTINF:-1,Two\nhttps://example.com/live', hint: 'wrong.json').single.name, 'Two');
  });

  test('UTF-16 LE and BE and Latin-1 playlists load', () {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    const source = '#EXTINF:-1,Café\nhttps://example.com/live';
    final le = [0xff, 0xfe, for (final c in source.codeUnits) ...[c & 255, c >> 8]];
    final be = [0xfe, 0xff, for (final c in source.codeUnits) ...[c >> 8, c & 255]];
    for (final bytes in [le, be, latin1.encode(source), utf8.encode('\uFEFF$source')]) {
      expect(repo.loadBytes(bytes).single.name, 'Café');
    }
  });

  test('JSON trailing commas repaired without changing commas in strings', () async {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    final result = await repo.loadBytesDetailed(utf8.encode('[{"name":"One,]","url":"https://example.com/live",},]'));
    expect(result.channels.single.name, 'One,]');
    expect(result.notes, isNotEmpty);
  });

  test('empty, HTML, arbitrary text and truncated JSON fail clearly', () {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    for (final raw in ['', '<!DOCTYPE html><html>Login</html>', 'junk', '[{"name":']) {
      expect(() => repo.parse(raw), throwsA(isA<PlaylistException>()));
    }
  });

  test('HLS manifest is one channel and never a segment catalogue', () {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    const manifest = '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\na.ts\n#EXTINF:10,\nb.ts';
    final result = repo.parse(manifest, hint: 'https://example.com/live.m3u8');
    expect(result, hasLength(1));
    expect(result.single.url, 'https://example.com/live.m3u8');
    expect(() => repo.parse(manifest, hint: 'local.m3u8'), throwsA(isA<PlaylistException>()));
  });

  test('URL validation rejects missing hosts and unrelated schemes', () {
    for (final url in ['https://', 'file:///tmp/list', 'example.com/list', 'https://a b/list']) {
      expect(() => PlaylistRepository.validateUrl(url), throwsA(isA<PlaylistException>()));
    }
  });

  test('redirect final URL is used to resolve relative streams', () async {
    final repo = PlaylistRepository(client: MockClient((request) async {
      if (request.url.path == '/start') {
        return http.Response('', 302, headers: {'location': '/folder/list.m3u'});
      }
      return http.Response('#EXTINF:-1,One\n./live.m3u8', 200);
    }));
    addTearDown(repo.dispose);
    final result = await repo.loadUrlDetailed('https://example.com/start');
    expect(result.channels.single.url, 'https://example.com/folder/live.m3u8');
  });

  test('server status errors do not expose URL credentials', () async {
    final repo = PlaylistRepository(client: MockClient((_) async => http.Response('Secret body', 403)));
    addTearDown(repo.dispose);
    await expectLater(repo.loadUrlDetailed('https://example.com/list?password=secret'),
      throwsA(isA<PlaylistException>().having((e) => e.message, 'safe error',
        allOf(contains('403'), isNot(contains('secret'))))));
  });

  test('redirect loop is bounded', () async {
    var requests = 0;
    final repo = PlaylistRepository(client: MockClient((_) async {
      requests++;
      return http.Response('', 302, headers: {'location': '/loop'});
    }));
    addTearDown(repo.dispose);
    await expectLater(repo.loadUrlDetailed('https://example.com/loop'), throwsA(isA<PlaylistException>()));
    expect(requests, 6);
  });

  test('size limit applies before parsing', () async {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    await expectLater(repo.loadBytesDetailed(Uint8List(PlaylistRepository.maxBytes + 1)),
      throwsA(isA<PlaylistException>()));
  });

  test('large import matches the synchronous parser result', () async {
    final repo = PlaylistRepository();
    addTearDown(repo.dispose);
    final source = List.generate(4000, (i) => '#EXTINF:-1 group-title="Group",Channel $i\nhttps://example.com/$i').join('\n');
    final bytes = utf8.encode(source);
    expect(bytes.length, greaterThan(128 * 1024));
    final asyncResult = await repo.loadBytesDetailed(bytes);
    final syncResult = repo.loadBytes(bytes);
    expect(asyncResult.channels.map((c) => c.toJson()), syncResult.map((c) => c.toJson()));
  });
}
