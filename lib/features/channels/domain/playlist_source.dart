enum PlaylistSourceType { url, localFile }

class PlaylistSource {
  const PlaylistSource({
    required this.id,
    required this.name,
    required this.location,
    required this.type,
  });

  final String id;
  final String name;
  final String location;
  final PlaylistSourceType type;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'type': type.name,
      };

  factory PlaylistSource.fromJson(Map<String, dynamic> json) => PlaylistSource(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String,
        type: PlaylistSourceType.values.byName(json['type'] as String),
      );
}
