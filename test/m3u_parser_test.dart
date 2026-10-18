import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/features/channels/data/m3u_parser.dart';

void main() {
  test('parses M3U metadata and headers', () {
    const source = '''
#EXTM3U
#EXTINF:-1 tvg-id="news.id" tvg-name="News ID" tvg-logo="https://img/logo.png" group-title="News",News ID HD
#EXTVLCOPT:http-user-agent=NontonTV-Test
#EXTVLCOPT:http-referrer=https://example.com/
https://example.com/live.m3u8
''';

    final channels = M3uParser().parse(source);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'News ID HD');
    expect(channels.single.group, 'News');
    expect(channels.single.tvgId, 'news.id');
    expect(channels.single.userAgent, 'NontonTV-Test');
    expect(channels.single.referrer, 'https://example.com/');
  });

  test('parses NontonTV KODIPROP ClearKey and Widevine DRM', () {
    const source = '''
#EXTM3U
#EXTINF:-1 group-title="DRM",ClearKey TV
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=00112233445566778899AABBCCDDEEFF:FFEEDDCCBBAA99887766554433221100
https://example.com/clearkey.mpd
#KODIPROP:inputstream.adaptive.license_type=com.widevine.alpha
#KODIPROP:inputstream.adaptive.license_key=https://license.example.com/wv
#EXTINF:-1 group-title="DRM",Widevine TV
https://example.com/widevine.mpd
''';

    final channels = M3uParser().parse(source);
    expect(channels, hasLength(2));
    expect(channels[0].drmType, 'clearkey');
    expect(channels[0].drmKey, contains(':'));
    expect(channels[1].drmType, 'com.widevine.alpha');
    expect(channels[1].drmKey, 'https://license.example.com/wv');
  });
}
