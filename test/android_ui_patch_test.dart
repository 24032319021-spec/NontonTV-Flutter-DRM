import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../scripts/apply_sitorustv_ui.dart';

void main() {
  test('UI Activity hook is idempotent and preserves all original player code', () {
    final original = File('native_android/app/src/main/kotlin/com/example/nontontv_flutter/MainActivity.kt').readAsStringSync();
    final patched = patchMainActivity(original);
    expect(patchMainActivity(patched), patched);
    expect('"setFullscreen"'.allMatches(patched), hasLength(1));
    final restored = patched.replaceFirst(RegExp(
      r'\n\s*// SitorusTV window UI hook v1\n\s*"setFullscreen" -> \{\n\s*TvWindowUi.apply\(this\)\n\s*result.success\(null\)\n\s*\}\n'), '');
    expect(restored, original);
  });

  test('branding preserves activity identity, PiP, permissions and theme metadata', () {
    final original = File('native_android/app/src/main/AndroidManifest.xml').readAsStringSync();
    final patched = patchManifest(original);
    expect(patchManifest(patched), patched);
    final restored = patched
      .replaceFirst('android:label="SitorusTV"', 'android:label="NontonTV Flutter"')
      .replaceFirst('android:icon="@mipmap/ic_sitorustv"', 'android:icon="@mipmap/ic_launcher"')
      .replaceFirst('android:banner="@drawable/sitorustv_loading"', 'android:banner="@mipmap/ic_launcher"')
      .replaceFirst('android:theme="@style/SitorusLaunchTheme"', 'android:theme="@style/LaunchTheme"');
    expect(restored, original);
  });

  test('unknown Activity or manifest is rejected before writes', () {
    expect(() => patchMainActivity('class MainActivity {}'), throwsFormatException);
    expect(() => patchManifest('<manifest/>'), throwsFormatException);
  });
}
