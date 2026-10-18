import 'package:flutter/services.dart';

class PlayerCapabilities {
  const PlayerCapabilities({
    required this.media3Version,
    required this.ffmpegAvailable,
  });

  final String media3Version;
  final bool ffmpegAvailable;
}

class AndroidTvPlatform {
  static const MethodChannel _channel = MethodChannel('nontontv/platform');

  static Future<bool> enterPictureInPicture({int width = 16, int height = 9}) async {
    try {
      return await _channel.invokeMethod<bool>('enterPip', {
            'width': width,
            'height': height,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setAutoStartOnBoot(bool enabled) async {
    await _channel.invokeMethod<void>('setAutoStartOnBoot', {'enabled': enabled});
  }

  static Future<String?> getApplicationFilesDirectory() async {
    try {
      return await _channel.invokeMethod<String>('getApplicationFilesDirectory');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> getAutoStartOnBoot() async {
    try {
      return await _channel.invokeMethod<bool>('getAutoStartOnBoot') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<PlayerCapabilities?> getPlayerCapabilities() async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>('getPlayerCapabilities');
      if (raw == null) return null;
      return PlayerCapabilities(
        media3Version: '${raw['media3Version'] ?? 'unknown'}',
        ffmpegAvailable: raw['ffmpegAvailable'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
