// Run from the project: dart run scripts/apply_sitorustv_ui.dart
// Updates only branding/window UI in an existing generated Android shell.
import 'dart:io';

const uiHookMarker = '// SitorusTV window UI hook v1';

String patchMainActivity(String source) {
  if (source.contains(uiHookMarker)) return source;
  const anchor = 'when (call.method) {';
  if (!source.contains('package com.example.nontontv_flutter') ||
      anchor.allMatches(source).length != 1) {
    throw const FormatException('MainActivity tidak sesuai bridge proyek ini. Tidak ada file yang diubah.');
  }
  return source.replaceFirst(anchor, '''when (call.method) {
                $uiHookMarker
                "setFullscreen" -> {
                    TvWindowUi.apply(this)
                    result.success(null)
                }
''');
}

String _attribute(String tag, String name, String value) {
  final pattern = RegExp('$name="[^"]*"');
  if (pattern.hasMatch(tag)) return tag.replaceFirst(pattern, '$name="$value"');
  return tag.replaceFirst('>', ' $name="$value">');
}

String patchManifest(String source) {
  final application = RegExp(r'<application\b[^>]*>');
  if (application.allMatches(source).length != 1) {
    throw const FormatException('Tag application manifest tidak sesuai. Tidak ada file yang diubah.');
  }
  var result = source.replaceFirstMapped(application, (match) {
    var tag = _attribute(match.group(0)!, 'android:label', 'SitorusTV');
    tag = _attribute(tag, 'android:icon', '@mipmap/ic_sitorustv');
    return _attribute(tag, 'android:banner', '@drawable/sitorustv_loading');
  });
  var count = 0;
  result = result.replaceAllMapped(RegExp(r'<activity\b[^>]*>'), (match) {
    final tag = match.group(0)!;
    if (!RegExp(r'android:name="(?:\.MainActivity|com\.example\.nontontv_flutter\.MainActivity)"')
        .hasMatch(tag)) {
      return tag;
    }
    count++;
    return _attribute(tag, 'android:theme', '@style/SitorusLaunchTheme');
  });
  if (count != 1) {
    throw const FormatException('Activity utama tidak ditemukan. Tidak ada file yang diubah.');
  }
  return result;
}

Future<void> applyUi(Directory root) async {
  final main = Directory('${root.path}/android/app/src/main');
  final manifest = File('${main.path}/AndroidManifest.xml');
  final activity = File('${main.path}/kotlin/com/example/nontontv_flutter/MainActivity.kt');
  final template = Directory('${root.path}/android_ui');
  final helper = File('${template.path}/TvWindowUi.kt');
  final logo = File('${root.path}/assets/images/sitorustv_logo.png');
  final loading = File('${root.path}/assets/images/sitorustv_loading.png');
  for (final file in [manifest, activity, helper, logo, loading]) {
    if (!file.existsSync()) {
      throw FileSystemException('File wajib belum ada. Salin folder android_ui, assets dan scripts dari ZIP; gunakan Android proyek yang sudah berjalan.', file.path);
    }
  }
  final resources = Directory('${template.path}/res');
  if (!resources.existsSync()) throw const FormatException('Folder android_ui/res belum ada.');
  final resourceFiles = resources.listSync(recursive: true).whereType<File>().toList();
  if (resourceFiles.isEmpty) throw const FormatException('Resource UI belum ada.');

  // Validate both transformations before performing any writes.
  final newManifest = patchManifest(await manifest.readAsString());
  final newActivity = patchMainActivity(await activity.readAsString());
  final backup = Directory('${root.path}/android/sitorustv-ui-backup');
  await backup.create(recursive: true);
  for (final entry in {manifest: 'AndroidManifest.xml', activity: 'MainActivity.kt'}.entries) {
    final target = File('${backup.path}/${entry.value}');
    if (!target.existsSync()) await entry.key.copy(target.path);
  }
  for (final file in resourceFiles) {
    final relative = file.path.substring(resources.path.length + 1);
    final target = File('${main.path}/res/$relative');
    await target.parent.create(recursive: true);
    await file.copy(target.path);
  }
  final imageDir = Directory('${main.path}/res/drawable-nodpi');
  await imageDir.create(recursive: true);
  await logo.copy('${imageDir.path}/sitorustv_logo.png');
  await loading.copy('${imageDir.path}/sitorustv_loading.png');
  await helper.copy('${activity.parent.path}/TvWindowUi.kt');
  await manifest.writeAsString(newManifest);
  await activity.writeAsString(newActivity);

  // Remove obsolete dialog from older releases. Copying a folder over an
  // existing project does not delete files that no longer belong to lib/.
  final obsoleteAddPlaylistDialog = File(
    '${root.path}/lib/features/channels/presentation/add_playlist_dialog.dart',
  );
  if (obsoleteAddPlaylistDialog.existsSync()) {
    await obsoleteAddPlaylistDialog.delete();
    stdout.writeln('File lama add_playlist_dialog.dart dihapus.');
  }

  stdout.writeln('UI SitorusTV terpasang: nama, ikon, splash, dan layar penuh.');
  stdout.writeln('Gradle, applicationId, playlist tersimpan, dan kode ExoPlayer tidak diubah.');
}

Future<void> main() async {
  final root = File.fromUri(Platform.script).parent.parent;
  try {
    await applyUi(root);
  } on FileSystemException catch (error) {
    stderr.writeln('Gagal memasang UI: ${error.message} ${error.path ?? ''}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Gagal memasang UI: ${error.message}');
    exitCode = 1;
  }
}
