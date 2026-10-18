# SitorusTV 0.6.2 — gambar pengguna dan proporsi foto referensi

Ini source Flutter, bukan APK terkompilasi. Nama tampilan menjadi SitorusTV; package aplikasi, penyimpanan playlist dan mesin native ExoPlayer tetap memakai proyek yang sama.

## Gambar yang dipasang

| File yang dikirim pengguna | Fungsi | Asset aplikasi |
| --- | --- | --- |
| menu didalam.png | Latar beranda/menu saluran | assets/images/sitorustv_menu.png |
| loading screen.png | Gambar loading saat inisialisasi; splash/banner Android | assets/images/sitorustv_loading.png |
| Logo sitorusTV dengan Ornamen Batak(2).png | Ikon launcher, menu playlist dan halaman pengaturan | assets/images/sitorustv_logo.png |

Ketiga gambar disalin persis, tanpa digambar ulang atau diubah pikselnya. Latar Google TV sebelumnya dikeluarkan dari paket. Gambar menu sudah memuat wordmark SitorusTV; header tidak menggambar judul kedua di atasnya. Latar menu memakai seluruh frame gambar (BoxFit.fill). Loading landscape memakai cover agar memenuhi layar; tidak ditambahkan waktu tunggu buatan.

## Layout sesuai foto

Acuan utama: photo_2026-10-06_03-01-30.jpg, 1280 x 576. Foto photo_2026-10-06_03-00-47.jpg menunjukkan masalah versi lama: bilah sistem HP, empat kolom, judul kategori besar, bingkai kartu dan logo terlalu kecil.

| Komponen | Ukuran acuan pada lebar 1280 |
| --- | --- |
| Header | 76 |
| Sidebar kiri | 320 (25% lebar layar) |
| Saluran per baris landscape | 5 |
| Tinggi satu baris saluran | 232 |
| Kotak logo saluran | 136 x 136 |
| Tinggi minimum kategori | 60 + jarak 10 |
| Ukuran teks kategori/nama saluran | 22 |

Ukuran landscape dihitung proporsional terhadap lebar viewport, bukan ambang grid yang berubah mengikuti density Android. Logo memakai contain; gambar landscape di dalam logo tidak dipaksa menjadi persegi. Nama diletakkan di bawah logo, dengan pemisah tipis per baris dan tanpa bingkai kartu/favorit di tiap logo.

Sidebar menampilkan kategori menurut urutan playlist, memilih kategori pertama saat sumber baru dimuat. Filter Semua/Favorit dan pemilih sumber dipindahkan ke menu logo agar ruang kategori sesuai contoh. Portrait tetap mempunyai fallback dua kolom.

- Ketuk area tulisan/logo SitorusTV di kiri atas untuk Playlist & favorit.
- Tambah playlist juga tersedia di Pengaturan > Playlist.
- Tekan lama saluran atau tombol Menu remote untuk menambah/menghapus favorit.
- Search, refresh, settings dan tutup aplikasi ada di kanan atas.
- Tombol close player tetap tersedia seperti patch sebelumnya.

Proporsi ini diukur dari foto, bukan klaim hasil render Flutter identik piksel di setiap perangkat. Font sistem, cutout kamera, rasio layar dan logo dari playlist dapat memengaruhi hasil akhir.

## Layar penuh dan branding Android

TvDisplayScope meminta mode layar penuh saat aplikasi dimulai/kembali aktif dan memulihkannya setelah keyboard ditutup. Player tidak lagi mengembalikan beranda ke edge-to-edge dengan bilah sistem terlihat. Hook UI Android menggunakan WindowInsetsController untuk API 30+, dengan fallback immersive flags untuk versi lama. Bilah sistem tetap bisa dibuka sementara lewat swipe tepi, sesuai perilaku Android. PiP tidak dipaksa fullscreen oleh hook native.

Skrip scripts/apply_sitorustv_ui.dart memasang UI pada folder android yang SUDAH ada:

- Mengganti label SitorusTV, ikon, banner, dan launch theme pada manifest.
- Menambahkan satu cabang setFullscreen pada MethodChannel di MainActivity.
- Menyalin helper TvWindowUi dan resource branding.
- Membuat backup awal manifest/MainActivity di android/sitorustv-ui-backup.
- Tidak mengubah Gradle, target SDK, applicationId, paket Kotlin, kode direktori player, atau database/preferensi. Menjalankan ulang skrip tidak menggandakan hook.

Sembilan berkas baseline native_android/build tetap identik dengan arsip awal. Perlu dibedakan: skrip ini memang menambah hook UI pada MainActivity GENERATED di folder android pengguna; ia tidak mengubah source native_android baseline maupun kode ExoPlayer. Dart bridge tetap hanya memiliki penghapusan cast dari revisi 0.4.1.

## Pasang pada proyek Windows yang sudah berjalan

1. Hentikan debug/tekan q pada sesi flutter run lama.
2. Ekstrak ZIP ke folder sementara. Dari folder NontonTV-Flutter-DRM hasil ekstrak, salin lib, assets, test, scripts, android_ui dan pubspec.yaml ke D:\NontonTV-Flutter-DRM; ganti berkas yang sama.
3. Pertahankan folder android yang sudah ada. Jangan menjalankan bootstrap untuk update ini.
4. Jalankan dari root proyek:

```powershell
flutter pub get
dart run scripts/apply_sitorustv_ui.dart
flutter analyze
flutter test --reporter expanded 2>&1 | Tee-Object -FilePath hasil-test.txt
flutter run
```

Langkah apply_sitorustv_ui wajib untuk ikon/nama Android dan fullscreen modern. Tunggu pesan berhasil sebelum flutter run. Hentikan aplikasi sepenuhnya; hot reload saja tidak menerapkan perubahan Android/asset. Tetap gunakan kotlin.incremental=false pada android/gradle.properties bila sebelumnya diperlukan.

Untuk pemasangan pertama saja: jalankan bootstrap asli, lalu apply_sitorustv_ui, baru build. Jika suatu saat bootstrap diulang, terapkan ulang UI karena bootstrap membuat shell Android baru.

## Status pemeriksaan

Dijalankan di lingkungan revisi:

- Pemeriksaan delimiter dan import lokal pada source/test Dart, serta struktur script updater.
- XML resource Android berhasil diparse.
- SHA-256 ketiga asset sama persis dengan gambar yang dilampirkan pengguna.
- Pemeriksaan teks hook MainActivity: jika blok UI tambahan dibuang, source kembali persis ke baseline.
- Sembilan source native/build baseline sama persis; Dart bridge hanya perubahan cast yang telah didokumentasikan.
- Sintaks shell dan integritas ZIP diperiksa.

Belum dijalankan: Dart analyzer, tes Flutter, eksekusi script updater Dart, kompilasi Kotlin/APK, render Flutter sebenarnya, benchmark dan playback di HP. SDK Flutter/Dart/Android tidak tersedia di lingkungan ini.

Tes disertakan untuk lima ukuran beranda, lima kolom/ukuran sidebar pada dua density, perubahan kategori, loading selama inisialisasi, patch UI Android yang idempoten, serta seluruh tes playlist dan sentuh sebelumnya. Ini cakupan tes yang disiapkan, bukan klaim semua tes lulus. Jika masih ada error, kirim hasil-test.txt lengkap.

## Uji di HP setelah pemasangan

Buka aplikasi, periksa gambar loading dan nama/icon SitorusTV. Pastikan beranda landscape menampilkan lima saluran per baris tanpa bilah status/navigasi permanen. Coba ganti kategori, tambah playlist melalui logo/pengaturan, keyboard pencarian lalu tutup keyboard (pemulihan fullscreen sekitar 1,1 detik), buka player dan kembali ke beranda. Uji tap setelah kontrol player tersembunyi, tombol close, PiP, dan saluran DRM yang sebelumnya bekerja.

Perbaikan parser dari 0.4.x/0.5.1 tetap dipertahankan, termasuk header %ZZ yang tidak lagi menggagalkan playlist. Ini tidak menambah perbaikan stream mati atau lisensi DRM, dan bukan implementasi seluruh fitur OTT Navigator.

Kredit asli NontonTV oleh Hari Murti tetap terlihat di Pengaturan dan ORIGINAL_PROJECT_NOTICE.md.

Referensi API:
- https://developer.android.com/develop/ui/views/layout/immersive
- https://api.flutter.dev/flutter/services/SystemChrome/setEnabledSystemUIMode.html
