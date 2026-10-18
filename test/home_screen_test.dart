import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/core/theme/app_theme.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_controller.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_screen.dart';

import 'support/fakes.dart';

void main() {
  for (final size in [const Size(1280, 576), const Size(1280, 720), const Size(960, 540), const Size(640, 360), const Size(360, 640)]) {
    testWidgets('home fits $size and exposes close and search', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final controller = HomeController(repository: FakeRepository(), storage: FakeStorage());
      await controller.initialize();
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: HomeScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Tutup aplikasi'), findsOneWidget);
      expect(find.text('News'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-sidebar')),
        size.width >= 600 ? findsOneWidget : findsNothing);
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Cari channel'));
      await tester.pumpAndSettle();
      if (size.width > size.height) {
        tester.view.viewInsets = FakeViewPadding(bottom: size.height * .6);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(find.byType(TextField), 'no match');
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Tidak ada channel yang cocok.'), findsOneWidget);
      tester.view.resetViewInsets();
      await tester.tap(find.byTooltip('Tutup pencarian'));
      await tester.pumpAndSettle();
      expect(find.text('News'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets('add playlist opens direct playlist input without name popup', (tester) async {
    final controller = HomeController(repository: FakeRepository(), storage: FakeStorage());
    await controller.initialize();
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: HomeScreen(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Playlist & favorit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah playlist'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Tambahkan link playlist'), findsOneWidget);
    expect(find.textContaining('Nama playlist'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
