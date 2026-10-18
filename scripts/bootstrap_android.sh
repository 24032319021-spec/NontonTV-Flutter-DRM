#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v flutter >/dev/null 2>&1 || {
  echo "Flutter SDK tidak ditemukan di PATH." >&2
  exit 1
}

flutter create \
  --platforms=android \
  --org com.example \
  --project-name nontontv_flutter \
  "$TMP/bootstrap"

rm -rf "$ROOT/android"
cp -R "$TMP/bootstrap/android" "$ROOT/android"

TARGET="$ROOT/android/app/src/main/kotlin/com/example/nontontv_flutter"
mkdir -p "$TARGET"
cp "$ROOT/native_android/app/src/main/AndroidManifest.xml" "$ROOT/android/app/src/main/AndroidManifest.xml"
cp -R "$ROOT/native_android/app/src/main/kotlin/com/example/nontontv_flutter/." "$TARGET/"
mkdir -p "$ROOT/android/app/libs"
if compgen -G "$ROOT/native_android/app/libs/*" > /dev/null; then
  cp -R "$ROOT/native_android/app/libs/." "$ROOT/android/app/libs/"
fi

# Remove a generated activity in a different package/path.
find "$ROOT/android/app/src/main" -type f \( -name MainActivity.java -o -name MainActivity.kt \) \
  ! -path '*/com/example/nontontv_flutter/MainActivity.kt' -delete || true

GRADLE="$ROOT/android/app/build.gradle.kts"
cat >> "$GRADLE" <<'GRADLE_EOF'

// NontonTV native player bridge. Keep every Media3 module on exactly the same version.
dependencies {
    val media3Version = "1.11.1"
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-exoplayer-hls:$media3Version")
    implementation("androidx.media3:media3-exoplayer-dash:$media3Version")
    implementation("androidx.media3:media3-exoplayer-smoothstreaming:$media3Version")
    implementation("androidx.media3:media3-exoplayer-rtsp:$media3Version")
    implementation("androidx.media3:media3-datasource-rtmp:$media3Version")
    implementation("androidx.media3:media3-ui:$media3Version")

    // The FFmpeg extension is not published in Google Maven. If the matching AAR has
    // been built with scripts/build_media3_ffmpeg.sh, bootstrap copies it here.
    val ffmpegAar = file("libs/media3-decoder-ffmpeg-release.aar")
    if (ffmpegAar.exists()) {
        implementation(files(ffmpegAar))
    }
}
GRADLE_EOF

echo "Android shell siap dengan Media3 ExoPlayer 1.11.1."
if [[ -f "$ROOT/android/app/libs/media3-decoder-ffmpeg-release.aar" ]]; then
  echo "FFmpeg extension AAR: TERPASANG"
else
  echo "FFmpeg extension AAR: belum ada (opsional: ./scripts/build_media3_ffmpeg.sh lalu bootstrap ulang)"
fi
echo "Jalankan: flutter pub get && flutter run"
