#!/usr/bin/env bash
set -euo pipefail

# Builds a Media3 1.11.1 FFmpeg decoder AAR matching the ExoPlayer version used by this port.
# Official Media3 does not publish decoder_ffmpeg through Google Maven; it must be built locally.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_ROOT="${NONTONTV_FFMPEG_WORKDIR:-$ROOT/.ffmpeg-build}"
MEDIA3_VERSION="${MEDIA3_VERSION:-1.11.1}"
ANDROID_ABI="${ANDROID_ABI:-24}"
DECODER_STRING="${NONTONTV_FFMPEG_DECODERS:-vorbis opus flac alac mp3 aac ac3 eac3}"
read -r -a ENABLED_DECODERS <<< "$DECODER_STRING"

NDK_PATH="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK_PATH" ]]; then
  echo "Set ANDROID_NDK_HOME atau ANDROID_NDK_ROOT ke Android NDK. Media3 merekomendasikan NDK r26b." >&2
  exit 1
fi

for cmd in git cmake java; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd tidak ditemukan." >&2; exit 1; }
done

case "$(uname -s)" in
  Linux*) HOST_PLATFORM="linux-x86_64" ;;
  Darwin*) HOST_PLATFORM="darwin-x86_64" ;;
  *) echo "Script ini ditujukan untuk Linux/WSL/macOS." >&2; exit 1 ;;
esac

mkdir -p "$WORK_ROOT"
MEDIA_DIR="$WORK_ROOT/media-$MEDIA3_VERSION"
if [[ ! -d "$MEDIA_DIR/.git" ]]; then
  git clone --depth 1 --branch "$MEDIA3_VERSION" https://github.com/androidx/media.git "$MEDIA_DIR"
fi

FFMPEG_MODULE_PATH="$MEDIA_DIR/libraries/decoder_ffmpeg/src/main"
JNI_DIR="$FFMPEG_MODULE_PATH/jni"
if [[ ! -d "$JNI_DIR/ffmpeg/.git" ]]; then
  rm -rf "$JNI_DIR/ffmpeg"
  git clone --depth 1 --branch release/6.0 https://github.com/FFmpeg/FFmpeg.git "$JNI_DIR/ffmpeg"
fi

pushd "$JNI_DIR" >/dev/null
./build_ffmpeg.sh \
  "$FFMPEG_MODULE_PATH" \
  "$NDK_PATH" \
  "$HOST_PLATFORM" \
  "$ANDROID_ABI" \
  "${ENABLED_DECODERS[@]}"
popd >/dev/null

pushd "$MEDIA_DIR" >/dev/null
./gradlew lib-decoder-ffmpeg:assembleRelease
popd >/dev/null

AAR="$(find "$MEDIA_DIR/libraries/decoder_ffmpeg" -type f -name '*decoder-ffmpeg*release*.aar' | head -n 1 || true)"
if [[ -z "$AAR" ]]; then
  echo "Build selesai tetapi AAR tidak ditemukan di libraries/decoder_ffmpeg." >&2
  exit 1
fi

DEST="$ROOT/native_android/app/libs/media3-decoder-ffmpeg-release.aar"
cp "$AAR" "$DEST"
echo "FFmpeg AAR dibuat: $DEST"
echo "Jalankan scripts/bootstrap_android.sh kembali supaya AAR masuk ke android/app/libs."
