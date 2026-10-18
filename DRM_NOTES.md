# NontonTV DRM port notes

The original NontonTV player supports DRM by connecting playlist metadata to ExoPlayer's DRM session manager. This Flutter port keeps that behavior in the native Android Media3 layer.

## Original playlist behavior reproduced

### M3U

The parser recognizes:

```text
#KODIPROP:inputstream.adaptive.license_type=clearkey
#KODIPROP:inputstream.adaptive.license_key=<KID_HEX>:<KEY_HEX>
```

and:

```text
#KODIPROP:inputstream.adaptive.license_type=com.widevine.alpha
#KODIPROP:inputstream.adaptive.license_key=https://license.example/...
```

as well as PlayReady license types containing `playready`.

### JSON

Channels may reference a DRM entry using `drm_id`:

```json
{
  "categories": [
    {
      "name": "DRM",
      "channels": [
        {
          "name": "Example",
          "drm_id": "drm_wv",
          "stream_url": "https://cdn.example/manifest.mpd"
        }
      ]
    }
  ],
  "drm_licenses": [
    {
      "drm_id": "drm_wv",
      "drm_type": "widevine",
      "drm_key": "https://license.example/widevine"
    }
  ]
}
```

## Native Android mapping

`NontonTvPlayerView.kt` maps strings containing:

- `clearkey` -> `C.CLEARKEY_UUID`
- `widevine` -> `C.WIDEVINE_UUID`
- `playready` -> `C.PLAYREADY_UUID`

It then uses `DefaultDrmSessionManager.Builder` with `FrameworkMediaDrm.DEFAULT_PROVIDER`, matching the design used by the original NontonTV player.

- HTTP(S) `drm_key`: `HttpMediaDrmCallback`
- local ClearKey `KID:KEY`: `LocalMediaDrmCallback`
- multi-session enabled for non-ClearKey DRM, matching original NontonTV behavior

## Device limitations

App support is not the same as hardware certification. A device still needs the corresponding Android `MediaDrm` implementation and must satisfy the license server's policy. Examples include Widevine L1/L3 requirements, HDCP requirements, provisioning and PlayReady support.

FFmpeg is unrelated to DRM authentication/decryption. The optional FFmpeg extension only adds codec decoding fallback and does not require or provide DRM credentials.

Only use DRM streams, keys and license endpoints you are authorized to access.
