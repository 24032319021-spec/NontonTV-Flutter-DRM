/// Keep signed URLs intact. Never decode/re-encode an entire stream URL.
String cleanPlaylistText(String value) => value.replaceAll('\uFEFF', '').trim();

String? resolveStreamUrl(String value, {Uri? baseUri}) {
  var text = value.trim();
  if (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'")))) {
    text = text.substring(1, text.length - 1).trim();
  }
  if (text.isEmpty || RegExp(r'[\x00-\x20<>]').hasMatch(text)) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  const schemes = {'http', 'https', 'rtmp', 'rtmps', 'rtsp', 'udp', 'rtp'};
  if (uri.hasScheme) {
    return schemes.contains(uri.scheme.toLowerCase()) && uri.host.isNotEmpty
        ? text
        : null;
  }
  // Recover only paths that actually resemble stream references, not junk text.
  if (baseUri == null ||
      !(baseUri.scheme == 'http' || baseUri.scheme == 'https') ||
      !(text.startsWith('/') || text.startsWith('./') || text.startsWith('../') ||
          RegExp(r'\.(m3u8?|mpd|ts|mp4|mkv|m4v|aac|mp3)([?#]|$)', caseSensitive: false)
              .hasMatch(text))) {
    return null;
  }
  final resolved = baseUri.resolveUri(uri);
  return resolved.host.isNotEmpty ? resolved.toString() : null;
}

String safeDecodeHeader(String text) {
  try {
    return Uri.decodeComponent(text).trim();
  } on ArgumentError {
    // Uri.decodeComponent rejects malformed percent escapes (for example
    // %ZZ or a trailing %) with ArgumentError, rather than FormatException.
    return text.trim();
  } on FormatException {
    // Percent escapes can also decode into an invalid UTF-8 byte sequence.
    return text.trim();
  }
}

Map<String, String> parseHeaderPairs(String text) {
  final headers = <String, String>{};
  for (final pair in text.split(RegExp(r'[|&]'))) {
    final equals = pair.indexOf('=');
    if (equals <= 0) continue;
    final key = safeDecodeHeader(pair.substring(0, equals)).toLowerCase();
    final value = safeDecodeHeader(pair.substring(equals + 1));
    if (RegExp(r'^[a-z0-9!#$%&\x27*+.^_`~-]+$').hasMatch(key) &&
        value.isNotEmpty && !RegExp(r'[\r\n\x00]').hasMatch(value)) {
      headers[key == 'referrer' ? 'referer' : key] = value;
    }
  }
  return headers;
}
