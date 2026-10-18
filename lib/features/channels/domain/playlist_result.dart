import 'channel.dart';

/// Import diagnostics never contain stream URLs, credentials or DRM keys.
class PlaylistResult {
  PlaylistResult({
    required List<TvChannel> channels,
    this.skipped = 0,
    this.recovered = 0,
    this.duplicates = 0,
    this.notes = const [],
  }) : channels = List.unmodifiable(channels);

  final List<TvChannel> channels;
  final int skipped;
  final int recovered;
  final int duplicates;
  final List<String> notes;

  String get summary => [
        '${channels.length} channel siap',
        if (recovered > 0) '$recovered entri dipulihkan',
        if (skipped > 0) '$skipped entri dilewati',
        if (duplicates > 0) '$duplicates duplikat dihapus',
        ...notes,
      ].join(' · ');
}
