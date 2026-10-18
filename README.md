# SitorusTV — Flutter + Native ExoPlayer

## Upgrade 0.6.2

Branding SitorusTV menggunakan tiga gambar yang diberikan pengguna. Beranda mengikuti proporsi foto referensi: lima kolom landscape, sidebar 25%, logo saluran tanpa bingkai, nama di bawah, dan urutan kategori playlist. Fullscreen dipulihkan saat kembali dari player/keyboard. Mesin native ExoPlayer tetap dipertahankan.

**Update proyek yang sudah berjalan:** salin `lib`, `assets`, `test`, `scripts`, `android_ui`, dan `pubspec.yaml`; pertahankan folder `android`. Jalankan `flutter pub get`, **`dart run scripts/apply_sitorustv_ui.dart`**, lalu `flutter analyze`, `flutter test`, `flutter run`. Jangan bootstrap ulang. Ketuk logo kiri atas untuk playlist/favorit, atau tambah playlist dari pengaturan.

Lihat [catatan upgrade](UPGRADE_NOTES_ID.md). Source/asset/XML diperiksa, tetapi analyzer, tes Flutter, script updater Dart dan build Android belum dieksekusi karena SDK tidak tersedia di lingkungan revisi.

Flutter reimplementation of the open-source **NontonTV** Android TV/STB application by hariimurti.

Upstream project: https://github.com/hariimurti/NontonTV

> Important: this project keeps the upstream credit/distribution notice. Read `ORIGINAL_PROJECT_NOTICE.md` before redistributing or publishing a renamed build.

## Why the player is native Android

The NontonTV player is not treated as a generic Flutter video player. The UI, navigation, playlist handling, favorites, and settings are written in Flutter, while playback is hosted in a Flutter `AndroidView` backed by **AndroidX Media3 ExoPlayer**.

This is deliberate: it allows the player-specific NontonTV changes to be carried over directly at the Android layer.

### NontonTV player behavior carried over

The native bridge in `native_android/app/src/main/kotlin/com/example/nontontv_flutter/player/` contains:

- `DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON`
- optional **Media3 FFmpeg decoder extension** support
- NontonTV-style optimized prebuffer toggle
- the same custom buffer values used by the upstream patch:
  - min buffer: `32 * 1024 ms` = 32768 ms
  - max buffer: `64 * 1024 ms` = 65536 ms
  - buffer for playback: `1024 ms`
  - buffer after rebuffer: `1024 ms`
  - allocator segment size: `16` bytes, matching the upstream constructor value
  - target buffer bytes: unset / automatic (`C.LENGTH_UNSET`, modern equivalent of `-1`)
  - prioritize time over size thresholds: enabled
- optional custom User-Agent input when a playlist does not supply one
- custom per-stream HTTP headers
- auto retry after playback error/end
- unsupported-audio warning without intentionally blocking supported video playback
- video/audio/subtitle track enumeration and selection
- Fit / Fill / Zoom / Fixed Width / Fixed Height modes
- HLS, DASH, SmoothStreaming, progressive HTTP, RTSP, and RTMP modules

The historical NontonTV AV1 extension is intentionally **not** bundled: upstream later removed that extension. Device/platform AV1 decoding can still work when Android itself supports it.


## DRM support

This port now mirrors the original NontonTV DRM flow in the native Media3 ExoPlayer layer. DRM playback is handled by Android `MediaDrm`, not by Flutter and not by the optional FFmpeg extension.

Supported NontonTV playlist forms:

- **ClearKey** using a local `KID_HEX:KEY_HEX` value
- **Widevine** using an HTTP(S) license-server URL
- **PlayReady** using an HTTP(S) license-server URL on devices that provide PlayReady support
- original NontonTV JSON mapping through `channel.drm_id` -> top-level `drm_licenses`
- M3U/Kodi-style properties:

```text
#KODIPROP:inputstream.adaptive.license_type=com.widevine.alpha
#KODIPROP:inputstream.adaptive.license_key=https://license.example/...
#EXTINF:-1 group-title="DRM",Example
https://cdn.example/manifest.mpd
```

For ClearKey:

```text
#EXTINF:-1 group-title="DRM",ClearKey Example
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=<KID_HEX>:<KEY_HEX>
https://cdn.example/manifest.mpd
```

The same per-channel User-Agent/Referer headers are also used by the DRM HTTP callback, matching the original NontonTV approach. The app checks whether the device reports support for the requested crypto scheme before playback.

**Important:** DRM support in the app does not create DRM capability that the hardware/ROM does not have. Widevine security level (L1/L3), HDCP capability, provisioning, PlayReady availability, and license policy are device/server properties. A service that requires Widevine L1 will still require an L1-certified device. Use only license servers/keys you are authorized to access.

**FFmpeg is separate from DRM.** You do not need Android NDK or the FFmpeg AAR merely to use Widevine/ClearKey/PlayReady. FFmpeg is only an optional codec-decoder extension for formats the device decoder cannot handle.

## FFmpeg extension: important

Media3's FFmpeg decoder extension is **not distributed as a normal Google Maven artifact**. Therefore this repository does not include a precompiled third-party FFmpeg AAR.

The player already enables extension renderers. To make the FFmpeg renderer available at runtime, build the matching AAR once and then bootstrap Android again.

Linux / WSL / macOS:

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r26b
chmod +x scripts/build_media3_ffmpeg.sh
./scripts/build_media3_ffmpeg.sh
```

The script builds the Media3 `1.11.1` FFmpeg module with FFmpeg 6.0 and copies the result to:

```text
native_android/app/libs/media3-decoder-ffmpeg-release.aar
```

Then regenerate the Android shell:

```bash
./scripts/bootstrap_android.sh
```

On Windows, build FFmpeg from WSL, then run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_android.ps1
```

In the app, **Settings > Player** reports whether the FFmpeg extension is actually detected.

## Features in this port

- Android TV / STB focused landscape UI
- Android remote/D-pad navigation
- M3U/M3U8 playlist parser
- NontonTV JSON playlist parser
- local playlist file import
- playlist URL loading
- multiple playlist sources
- favorites
- remember last watched channel
- optional resume of last channel
- native Media3 ExoPlayer playback
- NontonTV-compatible ClearKey / Widevine / PlayReady DRM handling
- NontonTV optimized prebuffer setting
- custom User-Agent input (no random checkbox)
- native video/audio/subtitle track selection
- player screen modes
- Picture-in-Picture bridge
- Android TV launcher intent
- optional launch after boot
- automatic playback retry

## Player controls

The Flutter player follows the upstream navigation model:

- Play/Pause media key: play / pause
- Rewind / Fast Forward: seek
- Left / Media Previous / swipe right: previous channel
- Right / Media Next / swipe left: next channel
- Up / Page Up / swipe down: previous category
- Down / Page Down / swipe up: next category
- Menu: player settings / track selection
- Center / Enter: show controls and focus play/pause; D-pad navigates buttons while controls have focus
- Tap video: show controls immediately; close stays available in the top-right corner
- Double-tap video: play / pause

## Requirements

This snapshot targets a modern Flutter/Dart toolchain and **Android API 24+**. The native Media3 dependencies are pinned to the same version (`1.11.1`) by the bootstrap scripts.

Older Android 4.4/5/6 STBs require a separate legacy compatibility branch/toolchain. Do not simply lower `minSdk` on a current Flutter project and expect Media3/Flutter compatibility.

## First setup

### Windows

```powershell
cd NontonTV-Flutter
powershell -ExecutionPolicy Bypass -File .\scripts\bootstrap_android.ps1
flutter pub get
dart run scripts/apply_sitorustv_ui.dart
flutter analyze
flutter test
flutter run
```

### Linux / macOS

```bash
cd NontonTV-Flutter
chmod +x scripts/bootstrap_android.sh
./scripts/bootstrap_android.sh
flutter pub get
dart run scripts/apply_sitorustv_ui.dart
flutter analyze
flutter test
flutter run
```

If you want the FFmpeg renderer, run `scripts/build_media3_ffmpeg.sh` **before** the Android bootstrap, or bootstrap again after the AAR is built.

## Release APK

```bash
flutter build apk --release --split-per-abi
```

## Project layout

```text
lib/
  core/platform/                 Android platform bridge
  features/channels/             playlists, channel model, home UI/state
  features/player/native/        Dart side of native ExoPlayer bridge
  features/player/presentation/  Flutter player UI + D-pad/touch controls
  features/settings/             player/application settings
  storage/                       persisted preferences

native_android/
  app/src/main/AndroidManifest.xml
  app/src/main/kotlin/.../
    MainActivity.kt
    BootReceiver.kt
    player/
      NontonTvPlayerViewFactory.kt
      NontonTvPlayerView.kt
  app/libs/                      generated FFmpeg AAR goes here

scripts/
  bootstrap_android.sh
  bootstrap_android.ps1
  build_media3_ffmpeg.sh
```

## Architecture note

`flutter create` owns the generated Android Gradle shell. Native overrides are stored separately in `native_android/` so the repository is easier to maintain across Flutter SDK upgrades. The bootstrap scripts create a fresh Android shell, copy the NontonTV native layer into it, and inject the matching Media3 dependencies.

## Verification status

The source was statically checked in the packaging environment. That environment does not contain Flutter SDK, Android SDK, or Android NDK, so an actual `flutter analyze`, Gradle compile, FFmpeg native build, and APK installation could not be executed there. Run the commands above on your Flutter/Android development machine before publishing.
