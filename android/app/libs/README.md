# Native player libraries

Place the generated Media3 FFmpeg decoder AAR here as:

`media3-decoder-ffmpeg-release.aar`

Use `scripts/build_media3_ffmpeg.sh` to build it. The Android bootstrap scripts copy the AAR into `android/app/libs/` and add it as a file dependency when it exists.

The AAR is intentionally not prebundled in this source package.
