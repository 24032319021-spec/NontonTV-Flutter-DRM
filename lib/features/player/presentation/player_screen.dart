import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';

import '../../../core/platform/android_tv_platform.dart';
import '../../../core/platform/tv_display.dart';
import '../../channels/domain/channel.dart';
import '../../channels/presentation/home_controller.dart';
import '../native/native_exoplayer_controller.dart';
import 'player_interaction_layer.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.homeController,
  });

  final List<TvChannel> channels;
  final int initialIndex;
  final HomeController homeController;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

enum _ScreenMode { fit, fill, zoom, fixedWidth, fixedHeight }

class _PlayerScreenState extends State<PlayerScreen> {
  late final NativeExoPlayerController _player;
  late int _index;
  final FocusNode _focusNode = FocusNode(debugLabel: 'player');
  final FocusNode _playFocus = FocusNode(debugLabel: 'player-play-pause');
  Timer? _overlayTimer;
  bool _showOverlay = true;
  bool _viewReady = false;
  bool _controlsFocused = false;
  int _modalDepth = 0;
  Object? _lastPlayerUi;
  _ScreenMode _screenMode = _ScreenMode.fit;

  TvChannel get _channel => widget.channels[_index];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.channels.length - 1).toInt();
    _player = NativeExoPlayerController()..addListener(_onPlayerChanged);
    unawaited(TvDisplay.enterFullscreen());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _onPlayerChanged() {
    // Position ticks do not change this live-TV UI. Keep the native surface and
    // overlay from rebuilding for every playback position event.
    final next = (_player.playing, _player.buffering, _player.error, _player.warning);
    if (!mounted || next == _lastPlayerUi) return;
    _lastPlayerUi = next;
    setState(() {});
  }

  Future<void> _onNativeViewCreated(int viewId) async {
    await _player.attach(viewId);
    if (!mounted) return;
    _viewReady = true;
    await _player.setResizeMode(_screenMode.name);
    await _openCurrent();
    if (mounted) _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _overlayTimer?.cancel();
    _player.removeListener(_onPlayerChanged);
    unawaited(_player.releaseNative());
    _player.dispose();
    _focusNode.dispose();
    _playFocus.dispose();
    unawaited(TvDisplay.enterFullscreen());
    super.dispose();
  }

  Future<void> _openCurrent() async {
    if (!mounted) return;
    await widget.homeController.rememberChannel(_channel);
    if (!mounted || !_viewReady) return;
    final customUserAgent = widget.homeController.userAgent.trim();
    final effectiveChannel = _channel.userAgent?.trim().isNotEmpty == true ||
            customUserAgent.isEmpty
        ? _channel
        : _channel.copyWith(userAgent: customUserAgent);
    await _player.open(
      effectiveChannel,
      optimizePrebuffer: widget.homeController.optimizePrebuffer,
      randomUserAgent: false,
    );
    _showControls();
  }

  void _hideOverlayLater() {
    _overlayTimer?.cancel();
    if (!mounted || _modalDepth > 0 || _controlsFocused) return;
    _overlayTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showOverlay = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    if (!_showOverlay) setState(() => _showOverlay = true);
    _hideOverlayLater();
  }

  void _onControlsFocus(bool focused) {
    _controlsFocused = focused;
    if (focused) {
      _overlayTimer?.cancel();
    } else {
      _hideOverlayLater();
    }
  }

  void _beginModal() {
    _modalDepth++;
    _showControls();
  }

  void _endModal() {
    _modalDepth--;
    if (!mounted || _modalDepth > 0) return;
    _focusNode.requestFocus();
    _showControls();
  }

  Future<void> _changeChannel(int delta) async {
    if (widget.channels.length <= 1) return;
    setState(() {
      _index = (_index + delta) % widget.channels.length;
      if (_index < 0) _index += widget.channels.length;
    });
    await _openCurrent();
  }

  Future<void> _changeCategory(int delta) async {
    final groups = <String>[];
    for (final channel in widget.channels) {
      if (!groups.contains(channel.group)) groups.add(channel.group);
    }
    if (groups.length <= 1) return;
    final current = groups.indexOf(_channel.group);
    var target = (current + delta) % groups.length;
    if (target < 0) target += groups.length;
    final index = widget.channels.indexWhere((channel) => channel.group == groups[target]);
    if (index >= 0) {
      setState(() => _index = index);
      await _openCurrent();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    // Let the D-pad move between visible buttons when a control has focus.
    // With focus on the video it retains the channel/category shortcuts.
    if (!_focusNode.hasPrimaryFocus &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight ||
            key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.select)) {
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.mediaTrackPrevious ||
        key == LogicalKeyboardKey.navigatePrevious) {
      unawaited(_changeChannel(-1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.mediaTrackNext ||
        key == LogicalKeyboardKey.navigateNext) {
      unawaited(_changeChannel(1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp) {
      unawaited(_changeCategory(-1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.pageDown) {
      unawaited(_changeCategory(1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select) {
      _showControls();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _playFocus.requestFocus();
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.mediaPlayPause) {
      unawaited(_player.playOrPause());
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPlay) {
      unawaited(_player.play());
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaPause) {
      unawaited(_player.pause());
      _showControls();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaRewind) {
      unawaited(_seekBy(const Duration(seconds: -10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.mediaFastForward) {
      unawaited(_seekBy(const Duration(seconds: 10)));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.settings ||
        key == LogicalKeyboardKey.contextMenu ||
        key == LogicalKeyboardKey.tvMediaContext) {
      unawaited(_showPlayerMenu());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _seekBy(Duration delta) async {
    final target = _player.position + delta;
    await _player.seek(target.isNegative ? Duration.zero : target);
    _showControls();
  }

  String get _screenModeLabel => switch (_screenMode) {
        _ScreenMode.fit => 'Fit',
        _ScreenMode.fill => 'Fill',
        _ScreenMode.zoom => 'Zoom',
        _ScreenMode.fixedWidth => 'Fixed width',
        _ScreenMode.fixedHeight => 'Fixed height',
      };

  Future<void> _showPlayerMenu() async {
    _beginModal();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xF2161618),
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Wrap(
                runSpacing: 8,
                children: [
                  ListTile(
                    leading: const Icon(Icons.aspect_ratio_rounded),
                    title: const Text('Mode layar'),
                    subtitle: Text(_screenModeLabel),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_cycleScreenMode());
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.high_quality_rounded),
                    title: const Text('Track video / kualitas'),
                    subtitle: Text('${_player.videoTracks.length} tersedia'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_showTracks(NativeTrackType.video));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.audiotrack_rounded),
                    title: const Text('Track audio'),
                    subtitle: Text('${_player.audioTracks.length} tersedia'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_showTracks(NativeTrackType.audio));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.subtitles_rounded),
                    title: const Text('Subtitle'),
                    subtitle: Text('${_player.textTracks.length} tersedia'),
                    onTap: () {
                      Navigator.pop(context);
                      unawaited(_showTracks(NativeTrackType.text));
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.picture_in_picture_alt_rounded),
                    title: const Text('Picture in Picture'),
                    onTap: () async {
                      Navigator.pop(context);
                      await AndroidTvPlatform.enterPictureInPicture();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      widget.homeController.isFavorite(_channel)
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                    ),
                    title: Text(
                      widget.homeController.isFavorite(_channel)
                          ? 'Lepas dari favorit'
                          : 'Pin ke favorit',
                    ),
                    onTap: () async {
                      await widget.homeController.toggleFavorite(_channel);
                      if (context.mounted) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    _endModal();
  }

  Future<void> _cycleScreenMode() async {
    final values = _ScreenMode.values;
    setState(() {
      _screenMode = values[(values.indexOf(_screenMode) + 1) % values.length];
    });
    await _player.setResizeMode(_screenMode.name);
    _showControls();
  }

  List<NativeTrack> _tracksFor(NativeTrackType type) => switch (type) {
        NativeTrackType.video => _player.videoTracks,
        NativeTrackType.audio => _player.audioTracks,
        NativeTrackType.text => _player.textTracks,
      };

  String _trackDialogTitle(NativeTrackType type) => switch (type) {
        NativeTrackType.video => 'Pilih track video / kualitas',
        NativeTrackType.audio => 'Pilih track audio',
        NativeTrackType.text => 'Pilih subtitle',
      };

  Future<void> _showTracks(NativeTrackType type) async {
    final tracks = _tracksFor(type);
    _beginModal();
    await showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(_trackDialogTitle(type)),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              await _player.selectAuto(type);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Auto'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              await _player.disableTrack(type);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Off'),
          ),
          ...tracks.map(
            (track) => SimpleDialogOption(
              onPressed: track.supported
                  ? () async {
                      await _player.selectTrack(track);
                      if (context.mounted) Navigator.pop(context);
                    }
                  : null,
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    child: track.selected ? const Icon(Icons.check_rounded, size: 18) : null,
                  ),
                  Expanded(
                    child: Text(
                      _trackName(track),
                      style: TextStyle(color: track.supported ? null : Colors.white38),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    _endModal();
  }

  String _trackName(NativeTrack track) {
    final details = <String>[track.label];
    if (track.width != null && track.height != null) {
      details.add('${track.width}x${track.height}');
    }
    if (track.frameRate != null) details.add('${track.frameRate!.toStringAsFixed(0)} fps');
    if (track.language != null && track.language!.isNotEmpty && track.language != track.label) {
      details.add(track.language!);
    }
    if (track.codecs != null && track.codecs!.isNotEmpty) details.add(track.codecs!);
    if (!track.supported) details.add('tidak didukung');
    return details.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        },
        child: Focus(
          autofocus: true,
          focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: PlayerInteractionLayer(
            surface: AndroidView(
              viewType: 'nontontv/native_player',
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
              onPlatformViewCreated: (id) => unawaited(_onNativeViewCreated(id)),
            ),
            controlsVisible: _showOverlay,
            onInteraction: _showControls,
            onControlsFocusChanged: _onControlsFocus,
            onClose: () => Navigator.maybePop(context),
            onDoubleTap: () => unawaited(_player.playOrPause()),
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) unawaited(_changeChannel(1));
              if (velocity > 200) unawaited(_changeChannel(-1));
            },
            onVerticalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity < -200) unawaited(_changeCategory(1));
              if (velocity > 200) unawaited(_changeCategory(-1));
            },
            status: Stack(
              children: [
                if (!_viewReady || _player.buffering)
                  const Center(child: CircularProgressIndicator()),
                if (_player.error != null)
                  Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 720),
                      padding: const EdgeInsets.all(16),
                      color: const Color(0xC0000000),
                      child: Text('Playback error\n${_player.error}', textAlign: TextAlign.center),
                    ),
                  ),
                if (_player.warning != null && _player.error == null)
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 80,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        color: const Color(0xB8000000),
                        child: Text(_player.warning!,
                          style: const TextStyle(color: Colors.amberAccent)),
                      ),
                    ),
                  ),
              ],
            ),
            controls: _PlayerOverlay(
              channel: _channel,
              index: _index,
              total: widget.channels.length,
              playing: _player.playing,
              screenMode: _screenModeLabel,
              playFocus: _playFocus,
              onPrevious: () => _changeChannel(-1),
              onNext: () => _changeChannel(1),
              onPlayPause: _player.playOrPause,
              onRewind: () => _seekBy(const Duration(seconds: -5)),
              onForward: () => _seekBy(const Duration(seconds: 10)),
              onScreenMode: _cycleScreenMode,
              onMenu: _showPlayerMenu,
              onPip: () => AndroidTvPlatform.enterPictureInPicture(),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerOverlay extends StatelessWidget {
  const _PlayerOverlay({
    required this.channel,
    required this.index,
    required this.total,
    required this.playing,
    required this.screenMode,
    required this.playFocus,
    required this.onPrevious,
    required this.onNext,
    required this.onPlayPause,
    required this.onRewind,
    required this.onForward,
    required this.onScreenMode,
    required this.onMenu,
    required this.onPip,
  });

  final TvChannel channel;
  final int index;
  final int total;
  final bool playing;
  final String screenMode;
  final FocusNode playFocus;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onPlayPause;
  final VoidCallback onRewind;
  final VoidCallback onForward;
  final VoidCallback onScreenMode;
  final VoidCallback onMenu;
  final VoidCallback onPip;

  Widget _button(String label, IconData icon, VoidCallback onPressed) {
    return IconButton.filledTonal(
      tooltip: label,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xB3202020),
        foregroundColor: Colors.white,
        focusColor: const Color(0xB3FE9402),
        minimumSize: const Size(48, 48),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x99000000), Colors.transparent, Color(0xC0000000)],
          stops: [0, .45, 1],
        ),
      ),
      child: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 14,
              left: 20,
              right: 78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text('${channel.group.toUpperCase()}  ·  ${index + 1}/$total',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _button('Mundur 5 detik', Icons.replay_5_rounded, onRewind),
                  const SizedBox(width: 24),
                  IconButton.filledTonal(
                    tooltip: playing ? 'Pause' : 'Play',
                    focusNode: playFocus,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xB3202020),
                      foregroundColor: Colors.white,
                      focusColor: const Color(0xB3FE9402),
                      minimumSize: const Size(72, 72),
                      side: const BorderSide(color: Colors.white30),
                    ),
                    onPressed: onPlayPause,
                    iconSize: 40,
                    icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  const SizedBox(width: 24),
                  _button('Maju 10 detik', Icons.forward_10_rounded, onForward),
                ],
              ),
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  _button('Channel sebelumnya', Icons.skip_previous_rounded, onPrevious),
                  const SizedBox(width: 6),
                  _button('Channel berikutnya', Icons.skip_next_rounded, onNext),
                  const Spacer(),
                  _button('Mode layar: $screenMode', Icons.aspect_ratio_rounded, onScreenMode),
                  const SizedBox(width: 6),
                  _button('Track & pengaturan', Icons.tune_rounded, onMenu),
                  const SizedBox(width: 6),
                  _button('Picture in Picture', Icons.picture_in_picture_alt_rounded, onPip),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
