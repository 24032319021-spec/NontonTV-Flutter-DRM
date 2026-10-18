# NontonTV ExoPlayer compatibility layer

This file records the player-specific behaviors intentionally preserved from upstream NontonTV.

## Implemented

1. Native Android ExoPlayer rather than a generic Flutter playback backend.
2. AndroidX Media3 `DefaultRenderersFactory` with extension renderer mode ON.
3. Optional Media3 FFmpeg audio decoder extension.
4. NontonTV optimized `DefaultLoadControl` values, toggleable from Flutter Settings.
5. Random User-Agent fallback for stream requests.
6. Playlist-provided HTTP headers take precedence over the random User-Agent fallback.
7. Automatic retry after errors/end-of-stream.
8. Unsupported audio is surfaced as a warning instead of triggering an application-level video stop.
9. Video/audio/text track discovery and explicit selection.
10. Fit, Fill, Zoom, Fixed Width, and Fixed Height display modes.
11. RTMP / RTSP / HLS / DASH / SmoothStreaming Media3 modules included by bootstrap.

## Deliberately not copied

- The old AV1 decoder extension. Upstream NontonTV added it and later removed it.
- A precompiled FFmpeg AAR. Media3's FFmpeg decoder is built locally because it is not a normal Maven artifact and contains native code compiled for the requested ABIs.

## Main implementation file

`native_android/app/src/main/kotlin/com/example/nontontv_flutter/player/NontonTvPlayerView.kt`

## Runtime verification

Open **Settings > Player** in the Flutter app. It shows:

- Media3 version
- whether `androidx.media3.decoder.ffmpeg.FfmpegLibrary.isAvailable()` reports the FFmpeg extension as available

This makes it possible to distinguish “extension mode enabled” from “FFmpeg binary actually packaged”.

## DRM port (added after initial Flutter port)

The initial Flutter package did not yet carry NontonTV's DRM path. The current package does.

The native Media3 bridge now mirrors the upstream player logic:

- maps DRM type strings containing `clearkey`, `widevine`, or `playready` to the corresponding Android/Media3 UUID
- checks `FrameworkMediaDrm.isCryptoSchemeSupported(...)`
- uses `HttpMediaDrmCallback` when `drm_key` is an HTTP(S) license URL
- uses `LocalMediaDrmCallback` for NontonTV-style local ClearKey `KID_HEX:KEY_HEX`
- uses `DefaultDrmSessionManager.Builder` + `FrameworkMediaDrm.DEFAULT_PROVIDER`
- uses single-session ClearKey and multi-session non-ClearKey, matching upstream NontonTV
- routes the DRM session manager through Media3 `setDrmSessionManagerProvider`, the modern replacement for the legacy media-source DRM setter

The Flutter M3U parser now understands NontonTV/Kodi `#KODIPROP:inputstream.adaptive.license_type` and `license_key` lines, including properties placed before or after `#EXTINF`. The JSON parser resolves the original `drm_id` -> `drm_licenses` relationship.

This enables normal authorized DRM playback. It does not bypass DRM or change a device's Widevine security level/certification.
