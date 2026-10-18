$ErrorActionPreference = "Stop"

$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nontontv_flutter_" + [System.Guid]::NewGuid().ToString("N"))
$Bootstrap = Join-Path $TempRoot "bootstrap"

try {
    if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
        throw "Flutter SDK tidak ditemukan di PATH."
    }

    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
    flutter create --platforms=android --org com.example --project-name nontontv_flutter $Bootstrap
    if ($LASTEXITCODE -ne 0) { throw "flutter create gagal." }

    $Android = Join-Path $Root "android"
    if (Test-Path $Android) { Remove-Item $Android -Recurse -Force }
    Copy-Item (Join-Path $Bootstrap "android") $Android -Recurse

    $TargetKotlin = Join-Path $Android "app\src\main\kotlin\com\example\nontontv_flutter"
    New-Item -ItemType Directory -Force -Path $TargetKotlin | Out-Null

    Copy-Item (Join-Path $Root "native_android\app\src\main\AndroidManifest.xml") (Join-Path $Android "app\src\main\AndroidManifest.xml") -Force
    Copy-Item (Join-Path $Root "native_android\app\src\main\kotlin\com\example\nontontv_flutter\*") $TargetKotlin -Recurse -Force

    $AndroidLibs = Join-Path $Android "app\libs"
    New-Item -ItemType Directory -Force -Path $AndroidLibs | Out-Null
    $NativeLibs = Join-Path $Root "native_android\app\libs"
    if (Test-Path $NativeLibs) {
        Get-ChildItem $NativeLibs -File | ForEach-Object {
            Copy-Item $_.FullName $AndroidLibs -Force
        }
    }

    Get-ChildItem (Join-Path $Android "app\src\main") -Recurse -File -Include MainActivity.kt,MainActivity.java |
        Where-Object { $_.FullName -ne (Join-Path $TargetKotlin "MainActivity.kt") } |
        Remove-Item -Force

    $Gradle = Join-Path $Android "app\build.gradle.kts"
    @'

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

    val ffmpegAar = file("libs/media3-decoder-ffmpeg-release.aar")
    if (ffmpegAar.exists()) {
        implementation(files(ffmpegAar))
    }
}
'@ | Add-Content -Path $Gradle

    Write-Host "Android shell siap dengan Media3 ExoPlayer 1.11.1."
    if (Test-Path (Join-Path $AndroidLibs "media3-decoder-ffmpeg-release.aar")) {
        Write-Host "FFmpeg extension AAR: TERPASANG"
    } else {
        Write-Host "FFmpeg extension AAR: belum ada. Build di Linux/WSL/macOS lalu jalankan bootstrap ulang."
    }
    Write-Host "Jalankan: flutter pub get; flutter run"
}
finally {
    if (Test-Path $TempRoot) { Remove-Item $TempRoot -Recurse -Force }
}
