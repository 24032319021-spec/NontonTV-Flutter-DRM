import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/features/channels/data/nontontv_json_parser.dart';

void main() {
  test('parses nested category JSON', () {
    const source = '''
{
  "categories": [
    {
      "title": "Nasional",
      "channels": [
        {"name": "Channel Satu", "url": "https://example.com/one.m3u8"}
      ]
    }
  ]
}
''';

    final channels = NontonTvJsonParser().parse(source);
    expect(channels, hasLength(1));
    expect(channels.single.name, 'Channel Satu');
    expect(channels.single.group, 'Nasional');
  });

  test('resolves original NontonTV drm_id from drm_licenses', () {
    const source = '''
{
  "categories": [
    {
      "name": "DRM",
      "channels": [
        {
          "name": "Widevine TV",
          "drm_id": "drm_wv",
          "stream_url": "https://example.com/widevine.mpd"
        }
      ]
    }
  ],
  "drm_licenses": [
    {
      "drm_id": "drm_wv",
      "drm_type": "widevine",
      "drm_key": "https://license.example.com/widevine"
    }
  ]
}
''';

    final channels = NontonTvJsonParser().parse(source);
    expect(channels, hasLength(1));
    expect(channels.single.drmId, 'drm_wv');
    expect(channels.single.drmType, 'widevine');
    expect(channels.single.drmKey, 'https://license.example.com/widevine');
  });
}
