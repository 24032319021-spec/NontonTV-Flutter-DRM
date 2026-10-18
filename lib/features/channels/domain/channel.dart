class TvChannel {
  const TvChannel({
    required this.id,
    required this.name,
    required this.url,
    required this.group,
    this.logo,
    this.tvgId,
    this.userAgent,
    this.referrer,
    this.drmId,
    this.drmType,
    this.drmKey,
    this.headers = const {},
  });

  final String id;
  final String name;
  final String url;
  final String group;
  final String? logo;
  final String? tvgId;
  final String? userAgent;
  final String? referrer;
  final Map<String, String> headers;

  /// NontonTV-compatible DRM fields.
  /// drmType accepts values containing clearkey, widevine or playready.
  /// drmKey is either KID:KEY for local ClearKey or an HTTP(S) license URL.
  final String? drmId;
  final String? drmType;
  final String? drmKey;

  bool get hasDrm =>
      drmType != null &&
      drmType!.trim().isNotEmpty &&
      drmKey != null &&
      drmKey!.trim().isNotEmpty;

  Map<String, String> get httpHeaders => {
        for (final entry in headers.entries)
          if (!{'user-agent', 'referer', 'referrer'}.contains(entry.key.toLowerCase()))
            entry.key: entry.value,
        if (userAgent != null && userAgent!.isNotEmpty) 'User-Agent': userAgent!,
        if (referrer != null && referrer!.isNotEmpty) 'Referer': referrer!,
      };

  TvChannel copyWith({String? group, String? userAgent}) => TvChannel(
        id: id,
        name: name,
        url: url,
        group: group ?? this.group,
        logo: logo,
        tvgId: tvgId,
        userAgent: userAgent ?? this.userAgent,
        referrer: referrer,
        drmId: drmId,
        drmType: drmType,
        drmKey: drmKey,
        headers: headers,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'group': group,
        if (logo != null) 'logo': logo,
        if (tvgId != null) 'tvgId': tvgId,
        if (userAgent != null) 'userAgent': userAgent,
        if (referrer != null) 'referrer': referrer,
        if (drmId != null) 'drmId': drmId,
        if (drmType != null) 'drmType': drmType,
        if (drmKey != null) 'drmKey': drmKey,
        if (headers.isNotEmpty) 'headers': headers,
      };

  factory TvChannel.fromJson(Map<String, dynamic> json) => TvChannel(
        id: '${json['id'] ?? json['url'] ?? json['name']}',
        name: '${json['name'] ?? 'Unknown'}',
        url: '${json['url'] ?? ''}',
        group: '${json['group'] ?? 'TV'}',
        logo: json['logo']?.toString(),
        tvgId: json['tvgId']?.toString(),
        userAgent: json['userAgent']?.toString(),
        referrer: json['referrer']?.toString(),
        drmId: json['drmId']?.toString(),
        drmType: json['drmType']?.toString(),
        drmKey: json['drmKey']?.toString(),
        headers: (json['headers'] as Map?)?.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            ) ?? const {},
      );

  @override
  bool operator ==(Object other) => other is TvChannel && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
