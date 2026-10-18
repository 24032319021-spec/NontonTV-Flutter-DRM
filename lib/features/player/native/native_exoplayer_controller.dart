import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../channels/domain/channel.dart';

enum NativeTrackType { video, audio, text }

class NativeTrack {
  const NativeTrack({
    required this.type,
    required this.groupIndex,
    required this.trackIndex,
    required this.label,
    required this.selected,
    required this.supported,
    this.language,
    this.codecs,
    this.width,
    this.height,
    this.frameRate,
    this.bitrate,
    this.channelCount,
    this.sampleRate,
  });

  final NativeTrackType type;
  final int groupIndex;
  final int trackIndex;
  final String label;
  final bool selected;
  final bool supported;
  final String? language;
  final String? codecs;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitrate;
  final int? channelCount;
  final int? sampleRate;

  factory NativeTrack.fromMap(Map<Object?, Object?> map) {
    final typeName = '${map['type'] ?? 'video'}';
    final type = switch (typeName) {
      'audio' => NativeTrackType.audio,
      'text' => NativeTrackType.text,
      _ => NativeTrackType.video,
    };
    return NativeTrack(
      type: type,
      groupIndex: (map['groupIndex'] as num?)?.toInt() ?? 0,
      trackIndex: (map['trackIndex'] as num?)?.toInt() ?? 0,
      label: '${map['label'] ?? 'Track'}',
      selected: map['selected'] == true,
      supported: map['supported'] != false,
      language: map['language']?.toString(),
      codecs: map['codecs']?.toString(),
      width: (map['width'] as num?)?.toInt(),
      height: (map['height'] as num?)?.toInt(),
      frameRate: (map['frameRate'] as num?)?.toDouble(),
      bitrate: (map['bitrate'] as num?)?.toInt(),
      channelCount: (map['channelCount'] as num?)?.toInt(),
      sampleRate: (map['sampleRate'] as num?)?.toInt(),
    );
  }
}

class NativeExoPlayerController extends ChangeNotifier {
  MethodChannel? _methods;
  EventChannel? _events;
  StreamSubscription<dynamic>? _eventSubscription;

  bool _initialized = false;
  bool _playing = false;
  bool _buffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _error;
  String? _warning;
  List<NativeTrack> _tracks = const [];

  bool get initialized => _initialized;
  bool get playing => _playing;
  bool get buffering => _buffering;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get error => _error;
  String? get warning => _warning;
  List<NativeTrack> get tracks => List.unmodifiable(_tracks);
  List<NativeTrack> get videoTracks => _tracks.where((e) => e.type == NativeTrackType.video).toList();
  List<NativeTrack> get audioTracks => _tracks.where((e) => e.type == NativeTrackType.audio).toList();
  List<NativeTrack> get textTracks => _tracks.where((e) => e.type == NativeTrackType.text).toList();

  Future<void> attach(int viewId) async {
    await _eventSubscription?.cancel();
    _methods = MethodChannel('nontontv/player/$viewId/methods');
    _events = EventChannel('nontontv/player/$viewId/events');
    _eventSubscription = _events!.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error) {
        _error = '$error';
        notifyListeners();
      },
    );
    _initialized = true;
    try {
      final state = await _methods!.invokeMapMethod<Object?, Object?>('getState');
      if (state != null) _applyState(state);
    } catch (_) {
      // A first state event normally follows immediately after attaching.
    }
    notifyListeners();
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;
    final map = Map<Object?, Object?>.from(event);
    switch ('${map['event'] ?? 'state'}') {
      case 'state':
        _applyState(map);
        return;
      case 'error':
        _error = map['message']?.toString();
        notifyListeners();
        return;
      case 'warning':
        _warning = map['message']?.toString();
        notifyListeners();
        return;
      case 'tracks':
        _readTracks(map['tracks']);
        notifyListeners();
        return;
    }
  }

  void _applyState(Map<Object?, Object?> map) {
    _playing = map['playing'] == true;
    _buffering = map['buffering'] == true;
    _position = Duration(milliseconds: (map['positionMs'] as num?)?.toInt() ?? 0);
    final duration = (map['durationMs'] as num?)?.toInt() ?? 0;
    _duration = Duration(milliseconds: duration < 0 ? 0 : duration);
    if (map.containsKey('error')) _error = map['error']?.toString();
    if (map.containsKey('warning')) _warning = map['warning']?.toString();
    if (map.containsKey('tracks')) _readTracks(map['tracks']);
    notifyListeners();
  }

  void _readTracks(Object? raw) {
    if (raw is! List) {
      _tracks = const [];
      return;
    }
    _tracks = raw
        .whereType<Map>()
        .map((e) => NativeTrack.fromMap(Map<Object?, Object?>.from(e)))
        .toList(growable: false);
  }

  Future<void> _command(String method, [Map<String, Object?>? arguments]) async {
    final channel = _methods;
    if (channel == null) return;
    await channel.invokeMethod<void>(method, arguments);
  }

  Future<void> open(
    TvChannel channel, {
    required bool optimizePrebuffer,
    required bool randomUserAgent,
  }) async {
    _error = null;
    _warning = null;
    notifyListeners();
    try {
      await _command('open', {
        'url': channel.url,
        'headers': channel.httpHeaders,
        'optimizePrebuffer': optimizePrebuffer,
        'randomUserAgent': randomUserAgent,
        'drmType': channel.drmType,
        'drmKey': channel.drmKey,
      });
    } on PlatformException catch (error) {
      _error = error.message ?? error.code;
      notifyListeners();
    }
  }

  Future<void> play() => _command('play');
  Future<void> pause() => _command('pause');
  Future<void> playOrPause() => _command('playOrPause');

  Future<void> seek(Duration position) => _command('seek', {
        'positionMs': position.inMilliseconds,
      });

  Future<void> setResizeMode(String mode) => _command('setResizeMode', {'mode': mode});

  Future<void> selectTrack(NativeTrack track) => _command('selectTrack', {
        'type': track.type.name,
        'groupIndex': track.groupIndex,
        'trackIndex': track.trackIndex,
      });

  Future<void> selectAuto(NativeTrackType type) => _command('selectAuto', {'type': type.name});

  Future<void> disableTrack(NativeTrackType type) => _command('disableTrack', {'type': type.name});

  Future<void> refreshState() async {
    final state = await _methods?.invokeMapMethod<Object?, Object?>('getState');
    if (state != null) _applyState(state);
  }

  Future<void> releaseNative() async {
    try {
      await _command('release');
    } catch (_) {
      // Platform view disposal also releases the player.
    }
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }
}
