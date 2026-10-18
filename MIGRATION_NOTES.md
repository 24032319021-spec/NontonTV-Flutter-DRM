# Migration notes: NontonTV Android -> Flutter

## Key decision

Playback is **not** migrated to a generic Flutter video package.

Flutter owns the application UI/state/navigation, but Android playback stays native through a `PlatformView` + `MethodChannel`/`EventChannel`. This is required to preserve the customized NontonTV ExoPlayer behavior as closely as practical while moving the rest of the app to Flutter.

## Mapping

| Upstream NontonTV behavior | Flutter port |
| --- | --- |
| Android UI/activity navigation | Flutter widgets + Navigator |
| ExoPlayer | AndroidX Media3 ExoPlayer native PlatformView |
| extension renderers | `EXTENSION_RENDERER_MODE_ON` |
| FFmpeg extension | optional locally built Media3 FFmpeg AAR |
| optimized prebuffer | direct custom `DefaultLoadControl` port, user-toggleable |
| custom User-Agent | injected only when the playlist does not already define User-Agent |
| player retry | native 3-second retry scheduling |
| unsupported audio | warning; player is not intentionally stopped if video is playable |
| track selection | Media3 `TrackSelectionOverride` bridged to Flutter |
| player screen modes | native `AspectRatioFrameLayout` resize modes |
| D-pad navigation | Flutter keyboard/remote handling |
| PiP | Android MethodChannel bridge |
| boot launch | native `BroadcastReceiver` |
| favorites / last channel | `SharedPreferences` |
| M3U + NontonTV JSON | Dart parsers |

## Upstream player patches represented here

### Extension renderer

NontonTV enabled ExoPlayer extension renderers so its bundled decoder extensions could be used. The port uses:

```kotlin
DefaultRenderersFactory(context)
    .setExtensionRendererMode(DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON)
```

Media3 still prefers the platform renderer in this mode and uses an extension renderer when appropriate.

### FFmpeg

Current Media3 does not publish the FFmpeg decoder as a ready-to-add Google Maven dependency. `scripts/build_media3_ffmpeg.sh` builds a matching local AAR and the bootstrap scripts include it automatically if present.

### Optimized prebuffer

The port preserves the values from the NontonTV optimization patch:

```text
minBufferMs                    32768
maxBufferMs                    65536
bufferForPlaybackMs             1024
bufferForPlaybackAfterRebuffer  1024
allocator                        DefaultAllocator(true, 16)
targetBufferBytes                automatic / unset
prioritizeTimeOverSize           true
```

This remains optional in Settings, defaulting to enabled.

### Unsupported audio

The upstream player was changed so an unsupported audio track does not automatically prevent the video from being shown. The Media3 bridge reports an unsupported-audio warning to Flutter and does not add an application-level stop solely because audio is unsupported.

### AV1

An earlier upstream change added AV1 + FFmpeg extension renderers, but the AV1 extension was later dropped upstream. This port therefore does not package a custom AV1 extension.

## Media3 migration

The original project uses the older ExoPlayer API. This port maps those behaviors to AndroidX Media3 rather than freezing the whole app on legacy ExoPlayer 2 APIs.

All Media3 modules added by the bootstrap are kept on the same version (`1.11.1`).

## FFmpeg build boundary

The source wiring for FFmpeg is included, but the generated FFmpeg AAR is deliberately not checked into this package. Building native FFmpeg requires a local Android NDK/toolchain and follows the Media3 extension build process.

## Validation boundary

The packaging environment had Java/Kotlin tooling but no Flutter SDK, Android SDK, or Android NDK. Static consistency checks were run, but the final app still needs a real Flutter/Gradle build on a configured development machine.
