import 'dart:convert';

import '../domain/channel.dart';
import '../domain/playlist_result.dart';
import 'playlist_utils.dart';

class M3uParser {
  static final RegExp _attribute = RegExp(
    r'''([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s,]+))''',
  );

  List<TvChannel> parse(String source, {Uri? baseUri}) =>
      parseDetailed(source, baseUri: baseUri).channels;

  PlaylistResult parseDetailed(String source, {Uri? baseUri}) {
    final channels = <TvChannel>[];
    final seen = <String>{};
    var metadata = <String, String>{};
    var headers = <String, String>{};
    String? title;
    var hasEntry = false;
    var repaired = false;
    var skipped = 0;
    var recovered = 0;
    var duplicates = 0;

    void reset() {
      metadata = <String, String>{};
      headers = <String, String>{};
      title = null;
      hasEntry = false;
      repaired = false;
    }

    for (final rawLine in const LineSplitter().convert(source)) {
      final line = rawLine.replaceAll('\uFEFF', '').trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();
      if (upper.startsWith('#EXTINF:')) {
        // An orphan EXTINF must not leak its DRM/header data into the next item.
        if (hasEntry) {
          skipped++;
          reset();
        }
        hasEntry = true;
        final content = line.substring(8);
        final comma = _titleSeparator(content);
        final attributes = comma < 0 ? content : content.substring(0, comma);
        for (final match in _attribute.allMatches(attributes)) {
          metadata[match.group(1)!.toLowerCase()] =
              (match.group(2) ?? match.group(3) ?? match.group(4)!).trim();
        }
        title = comma < 0 ? null : content.substring(comma + 1).trim();
        repaired = comma < 0 || title!.isEmpty;
        continue;
      }
      if (upper.startsWith('#EXTGRP:')) {
        metadata['group-title'] = line.substring(8).trim();
        continue;
      }
      if (upper.startsWith('#EXTVLCOPT:')) {
        final option = line.substring(11);
        final equals = option.indexOf('=');
        if (equals > 0) {
          final key = option.substring(0, equals).trim().toLowerCase();
          final value = option.substring(equals + 1).trim();
          if (key == 'http-user-agent') headers['user-agent'] = value;
          if (key == 'http-referrer' || key == 'http-referer') {
            headers['referer'] = value;
          }
          if (key == 'http-origin') headers['origin'] = value;
        }
        continue;
      }
      if (upper.startsWith('#EXTHTTP:')) {
        try {
          final value = jsonDecode(line.substring(9));
          if (value is Map) {
            for (final entry in value.entries) {
              if (entry.value is String) {
                headers[entry.key.toString().toLowerCase()] = entry.value as String;
              }
            }
          }
        } on FormatException {
          repaired = true; // A broken optional header does not drop the channel.
        }
        continue;
      }
      if (upper.startsWith('#KODIPROP:')) {
        final option = line.substring(10);
        final equals = option.indexOf('=');
        if (equals > 0) {
          final key = option.substring(0, equals).trim().toLowerCase();
          final value = option.substring(equals + 1).trim();
          if (key == 'inputstream.adaptive.license_type') metadata['drm-type'] = value;
          if (key == 'inputstream.adaptive.license_key') metadata['drm-key'] = value;
          if (key == 'inputstream.adaptive.stream_headers' ||
              key == 'inputstream.adaptive.manifest_headers') {
            headers.addAll(parseHeaderPairs(value));
          }
        }
        continue;
      }
      if (line.startsWith('#')) continue;

      final pipe = line.indexOf('|');
      final rawUrl = pipe < 0 ? line : line.substring(0, pipe);
      final mediaUrl = resolveStreamUrl(rawUrl, baseUri: baseUri);
      if (mediaUrl == null) {
        skipped++;
        reset();
        continue;
      }
      if (pipe >= 0) headers.addAll(parseHeaderPairs(line.substring(pipe + 1)));
      final name = _nonEmpty(title) ?? _nonEmpty(metadata['tvg-name']) ??
          _nonEmpty(metadata['tvg-id']) ?? 'Channel ${channels.length + 1}';
      final group = _nonEmpty(metadata['group-title']) ?? 'TV';
      final drmKey = _nonEmpty(metadata['drm-key']);
      final safeHeaders = <String, String>{};
      for (final entry in headers.entries) {
        safeHeaders.addAll(parseHeaderPairs(
          '${Uri.encodeComponent(entry.key)}=${Uri.encodeComponent(entry.value)}',
        ));
      }
      final channel = TvChannel(
        id: '${metadata['tvg-id'] ?? name}|$mediaUrl',
        name: name,
        url: mediaUrl,
        group: group,
        logo: _nonEmpty(metadata['tvg-logo']) == null ? null :
            resolveStreamUrl(metadata['tvg-logo']!, baseUri: baseUri),
        tvgId: _nonEmpty(metadata['tvg-id']),
        userAgent: safeHeaders['user-agent'] ?? metadata['user-agent'],
        referrer: safeHeaders['referer'] ?? metadata['referrer'] ?? metadata['referer'],
        headers: safeHeaders,
        drmType: _nonEmpty(metadata['drm-type']),
        drmKey: drmKey,
        drmId: drmKey,
      );
      // Keep distinct groups, headers and DRM variants, even for the same URL.
      final sortedHeaders = safeHeaders.keys.toList()..sort();
      final signature = jsonEncode([
        channel.id, channel.name, channel.group, channel.logo,
        channel.userAgent, channel.referrer, channel.drmType, channel.drmKey,
        for (final key in sortedHeaders) [key, safeHeaders[key]],
      ]);
      if (seen.add(signature)) {
        channels.add(channel);
        if (!hasEntry || repaired || mediaUrl != rawUrl.trim()) recovered++;
      } else {
        duplicates++;
      }
      reset();
    }
    if (hasEntry) skipped++;
    return PlaylistResult(
      channels: channels, skipped: skipped, recovered: recovered,
      duplicates: duplicates,
    );
  }

  String? _nonEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value.trim();

  int _titleSeparator(String value) {
    String? quote;
    for (var i = 0; i < value.length; i++) {
      final char = value[i];
      if (quote != null) {
        if (char == quote) quote = null;
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == ',') {
        return i;
      }
    }
    return -1;
  }
}
