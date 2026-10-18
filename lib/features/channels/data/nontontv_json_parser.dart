import 'dart:convert';

import '../domain/channel.dart';
import 'playlist_utils.dart';

class _DrmLicense {
  const _DrmLicense({required this.id, required this.type, required this.key});
  final String id;
  final String type;
  final String key;
}

/// Parser for the original NontonTV JSON schema plus common IPTV JSON variants.
class NontonTvJsonParser {
  List<TvChannel> parse(String source) {
    final decoded = jsonDecode(source);

    if (decoded is Map) {
      final root = Map<String, dynamic>.from(decoded);
      final exact = _parseOriginalNontonTv(root);
      if (exact.isNotEmpty) return _deduplicate(exact);
    }

    final result = <TvChannel>[];
    _walk(decoded, result, inheritedGroup: 'TV');
    return _deduplicate(result);
  }

  List<TvChannel> _parseOriginalNontonTv(Map<String, dynamic> root) {
    final rawCategories = root['categories'];
    if (rawCategories is! List) return const [];

    final drmLicenses = <String, _DrmLicense>{};
    final rawLicenses = root['drm_licenses'];
    if (rawLicenses is List) {
      for (final item in rawLicenses.whereType<Map>()) {
        final map = Map<String, dynamic>.from(item);
        final id = _firstString(map, const ['drm_id', 'id']);
        final type = _firstString(map, const ['drm_type', 'type']);
        final key = _firstString(map, const ['drm_key', 'key', 'license']);
        if (id != null && type != null && key != null) {
          drmLicenses[id] = _DrmLicense(id: id, type: type, key: key);
        }
      }
    }

    final out = <TvChannel>[];
    for (final categoryRaw in rawCategories.whereType<Map>()) {
      final category = Map<String, dynamic>.from(categoryRaw);
      final group = _firstString(category, const ['name', 'title', 'group']) ?? 'TV';
      final channels = category['channels'];
      if (channels is! List) continue;

      for (final channelRaw in channels.whereType<Map>()) {
        final map = Map<String, dynamic>.from(channelRaw);
        final url = _firstString(map, const ['stream_url', 'url', 'stream', 'link']);
        final name = _firstString(map, const ['name', 'channel_name', 'title']);
        if (url == null || name == null || !_isStreamUrl(url)) continue;

        final drmId = _firstString(map, const ['drm_id', 'drmId']);
        final license = drmId == null ? null : drmLicenses[drmId];
        final directDrmType = _firstString(map, const ['drm_type', 'drmType']);
        final directDrmKey = _firstString(map, const ['drm_key', 'drmKey', 'license']);

        out.add(TvChannel(
          id: _firstString(map, const ['id', 'tvg-id', 'tvg_id']) ?? '$name|$url',
          name: name,
          url: url,
          group: group,
          logo: _firstString(map, const ['logo_url', 'logo', 'icon', 'image', 'tvg-logo']),
          tvgId: _firstString(map, const ['tvg-id', 'tvg_id']),
          userAgent: _firstString(map, const ['user_agent', 'user-agent', 'userAgent']),
          referrer: _firstString(map, const ['referer', 'referrer']),
          drmId: drmId,
          drmType: directDrmType ?? license?.type,
          drmKey: directDrmKey ?? license?.key,
        ));
      }
    }
    return out;
  }

  void _walk(
    dynamic node,
    List<TvChannel> result, {
    required String inheritedGroup,
  }) {
    if (node is List) {
      for (final item in node) {
        _walk(item, result, inheritedGroup: inheritedGroup);
      }
      return;
    }

    if (node is! Map) return;
    final map = Map<String, dynamic>.from(node);

    final group = _firstString(map, const [
          'group',
          'group-title',
          'category',
          'category_name',
          'title',
        ]) ??
        inheritedGroup;

    final url = _firstString(map, const [
      'url',
      'stream',
      'stream_url',
      'streamUrl',
      'link',
      'src',
    ]);

    final name = _firstString(map, const [
      'name',
      'channel',
      'channel_name',
      'title',
    ]);

    if (url != null && name != null && _isStreamUrl(url)) {
      result.add(TvChannel(
        id: _firstString(map, const ['id', 'tvg-id', 'tvg_id']) ?? '$name|$url',
        name: name,
        url: url,
        group: _firstString(map, const ['group', 'group-title', 'category']) ?? inheritedGroup,
        logo: _firstString(map, const ['logo_url', 'logo', 'icon', 'image', 'tvg-logo']),
        tvgId: _firstString(map, const ['tvg-id', 'tvg_id']),
        userAgent: _firstString(map, const ['user-agent', 'user_agent', 'userAgent']),
        referrer: _firstString(map, const ['referrer', 'referer']),
        drmId: _firstString(map, const ['drm_id', 'drmId']),
        drmType: _firstString(map, const ['drm_type', 'drmType']),
        drmKey: _firstString(map, const ['drm_key', 'drmKey', 'license']),
      ));
    }

    for (final entry in map.entries) {
      if (entry.key == 'drm_licenses') continue;
      if (entry.value is List || entry.value is Map) {
        final childGroup = _groupForChild(entry.key, group);
        _walk(entry.value, result, inheritedGroup: childGroup);
      }
    }
  }

  String _groupForChild(String key, String fallback) {
    const generic = {
      'channels',
      'channel',
      'items',
      'data',
      'playlist',
      'categories',
      'category',
    };
    return generic.contains(key.toLowerCase()) ? fallback : key;
  }

  String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is num) return value.toString();
    }
    return null;
  }

  bool _isStreamUrl(String value) => resolveStreamUrl(value) != null;

  List<TvChannel> _deduplicate(List<TvChannel> input) {
    final map = <String, TvChannel>{};
    for (final channel in input) {
      map[jsonEncode(channel.toJson())] = channel;
    }
    return map.values.toList();
  }
}
