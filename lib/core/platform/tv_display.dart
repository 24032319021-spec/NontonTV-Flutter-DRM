import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

abstract final class TvDisplay {
  static const _channel = MethodChannel('nontontv/platform');

  static Future<void> enterFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Current Android targets can ignore Flutter's legacy SystemUiMode flags.
    // The small Activity UI hook uses WindowInsetsController on API 30+.
    try {
      await _channel.invokeMethod<void>('setFullscreen');
    } on MissingPluginException {
      // Allows widget tests and older native shells to use the Flutter path.
    } on PlatformException {
      // The Flutter fallback remains active if the host rejects a UI request.
    }
  }
}

class TvDisplayScope extends StatefulWidget {
  const TvDisplayScope({super.key, required this.child});
  final Widget child;

  @override
  State<TvDisplayScope> createState() => _TvDisplayScopeState();
}

class _TvDisplayScopeState extends State<TvDisplayScope> with WidgetsBindingObserver {
  Timer? _restoreTimer;
  bool _keyboardVisible = false;

  bool get _hasKeyboard => WidgetsBinding.instance.platformDispatcher.views
      .any((view) => view.viewInsets.bottom > 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _keyboardVisible = _hasKeyboard;
    unawaited(TvDisplay.enterFullscreen());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_hasKeyboard) {
      unawaited(TvDisplay.enterFullscreen());
    }
  }

  @override
  void didChangeMetrics() {
    final visible = _hasKeyboard;
    if (visible) _restoreTimer?.cancel();
    if (_keyboardVisible && !visible) {
      _restoreTimer?.cancel();
      // Android requires at least one second after the keyboard closes.
      _restoreTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted && !_hasKeyboard) unawaited(TvDisplay.enterFullscreen());
      });
    }
    _keyboardVisible = visible;
  }

  @override
  void dispose() {
    _restoreTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
