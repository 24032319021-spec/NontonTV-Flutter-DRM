import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../domain/channel.dart';
import '../domain/playlist_result.dart';
import '../domain/playlist_source.dart';
import 'm3u_parser.dart';
import 'nontontv_json_parser.dart';
import 'playlist_utils.dart';

class PlaylistException implements Exception {
  const PlaylistException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PlaylistRepository {
  PlaylistRepository({http.Client? client}) : _client = client ?? http.Client();

  static const maxBytes = 20 * 1024 * 1024;
  final http.Client _client;

  static Uri validateUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty || RegExp(r'[\s\x00-\x1f]').hasMatch(url.trim())) {
      throw const PlaylistException('Masukkan URL lengkap http:// atau https://.');
    }
    return uri;
  }

  Future<PlaylistResult> loadUrlDetailed(String url) async {
    var uri = validateUrl(url);
    final abort = Completer<void>();
    final timer = Timer(const Duration(seconds: 30), () => abort.complete());
    try {
      // Resolve redirects ourselves so relative channel URLs use the final URL.
      for (var redirect = 0; redirect <= 5; redirect++) {
        final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers['Accept'] =
              'application/json, application/x-mpegURL, audio/x-mpegurl, text/plain, */*';
        final response = await _client.send(request);
        if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
          await response.stream.listen((_) {}).cancel();
          final location = response.headers['location'];
          if (location == null || redirect == 5) {
            throw const PlaylistException('Terlalu banyak pengalihan URL playlist.');
          }
          uri = validateUrl(uri.resolve(location).toString());
          continue;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          await response.stream.listen((_) {}).cancel();
          throw PlaylistException(
            'Server playlist merespons HTTP ${response.statusCode}. Periksa URL atau akses penyedia.',
          );
        }
        if ((response.contentLength ?? 0) > maxBytes) {
          await response.stream.listen((_) {}).cancel();
          throw const PlaylistException('Ukuran playlist melebihi batas 20 MB.');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > maxBytes) {
            throw const PlaylistException('Ukuran playlist melebihi batas 20 MB.');
          }
          bytes.add(chunk);
        }
        timer.cancel();
        return await loadBytesDetailed(bytes.takeBytes(), hint: uri.toString());
      }
      throw const PlaylistException('URL playlist tidak dapat dimuat.');
    } on http.RequestAbortedException {
      throw const PlaylistException('Waktu unduh habis. Periksa koneksi lalu coba lagi.');
    } on http.ClientException {
      throw const PlaylistException('Playlist tidak dapat diunduh. Periksa koneksi dan alamat server.');
    } finally {
      timer.cancel();
    }
  }

  Future<List<TvChannel>> loadUrl(String url) async =>
      (await loadUrlDetailed(url)).channels;

  Future<PlaylistResult> loadBytesDetailed(List<int> bytes, {String hint = ''}) async {
    if (bytes.length > maxBytes) {
      throw const PlaylistException('Ukuran playlist melebihi batas 20 MB.');
    }
    final input = _ParseInput(bytes, hint);
    if (bytes.length >= 128 * 1024) {
      return compute(_parseBytes, input, debugLabel: 'playlist-import');
    }
    return _parseBytes(input);
  }

  List<TvChannel> loadBytes(List<int> bytes, {String hint = ''}) =>
      _parseBytes(_ParseInput(bytes, hint)).channels;

  List<TvChannel> parse(String raw, {String hint = ''}) =>
      _parseText(raw, hint).channels;

  Future<List<TvChannel>> load(PlaylistSource source, {List<int>? localBytes}) async {
    switch (source.type) {
      case PlaylistSourceType.url:
        return loadUrl(source.location);
      case PlaylistSourceType.localFile:
        if (localBytes == null) {
          throw StateError('Local bytes are required for a local playlist.');
        }
        return (await loadBytesDetailed(localBytes, hint: source.location)).channels;
    }
  }

  void dispose() => _client.close();
}

class _ParseInput {
  const _ParseInput(this.bytes, this.hint);
  final List<int> bytes;
  final String hint;
}

PlaylistResult _parseBytes(_ParseInput input) {
  final bytes = input.bytes;
  if (bytes.length > PlaylistRepository.maxBytes) {
    throw const PlaylistException('Ukuran playlist melebihi batas 20 MB.');
  }
  String text;
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
          (bytes[0] == 0xfe && bytes[1] == 0xff))) {
    final littleEndian = bytes[0] == 0xff;
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) :
          (bytes[i] << 8) | bytes[i + 1]);
    }
    text = String.fromCharCodes(units);
  } else {
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      // Legacy M3U files are often single-byte Latin-1 rather than UTF-8.
      text = latin1.decode(bytes);
    }
  }
  return _parseText(text, input.hint);
}

PlaylistResult _parseText(String raw, String hint) {
  final text = cleanPlaylistText(raw);
  if (text.isEmpty) throw const PlaylistException('Playlist kosong.');
  if (RegExp(r'^\s*<(?:!doctype\s+html|html|head|body)\b', caseSensitive: false)
      .hasMatch(text)) {
    throw const PlaylistException('URL mengarah ke halaman web/login. Gunakan tautan unduh playlist langsung.');
  }
  final candidate = Uri.tryParse(hint);
  final base = candidate != null && {'http', 'https'}.contains(candidate.scheme)
      ? candidate : null;

  // HLS manifests describe one stream, not a catalogue of TS segments/variants.
  if (RegExp(r'^\s*#EXT-X-(TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE|MEDIA|VERSION|PART-INF):',
      multiLine: true, caseSensitive: false).hasMatch(text)) {
    if (base == null) {
      throw const PlaylistException('Ini manifest HLS. Tambahkan URL manifest .m3u8 melalui Tambah URL.');
    }
    final name = base.pathSegments.where((e) => e.isNotEmpty).lastOrNull ?? base.host;
    return PlaylistResult(channels: [TvChannel(
      id: '$name|$base', name: name, url: base.toString(), group: 'TV',
    )], notes: const ['Manifest HLS dibaca sebagai satu channel']);
  }

  PlaylistResult result;
  // Content wins over an unreliable extension or Content-Type from a server.
  if (text.startsWith('{') || text.startsWith('[')) {
    var repaired = false;
    List<TvChannel> channels;
    try {
      channels = NontonTvJsonParser().parse(text);
    } on FormatException {
      try {
        channels = NontonTvJsonParser().parse(_removeTrailingCommas(text));
        repaired = true;
      } on FormatException {
        throw const PlaylistException('Struktur JSON rusak atau terpotong. Periksa file dari penyedia.');
      }
    }
    result = PlaylistResult(channels: channels,
      notes: repaired ? const ['Koma berlebih pada JSON dipulihkan'] : const []);
  } else {
    result = M3uParser().parseDetailed(text, baseUri: base);
  }
  if (result.channels.isEmpty) {
    throw const PlaylistException('Tidak ditemukan channel valid. Gunakan M3U/M3U8, daftar URL, atau JSON NontonTV.');
  }
  return result;
}

String _removeTrailingCommas(String text) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
    } else {
      if (c == '"') inString = true;
      if (c == ',') {
        var next = i + 1;
        while (next < text.length && text[next].trim().isEmpty) { next++; }
        if (next < text.length && (text[next] == '}' || text[next] == ']')) continue;
      }
      out.write(c);
    }
  }
  return out.toString();
}
