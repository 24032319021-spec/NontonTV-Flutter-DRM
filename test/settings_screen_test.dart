import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/core/theme/app_theme.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_controller.dart';
import 'package:nontontv_flutter/features/settings/presentation/settings_screen.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('settings uses three clean tabs', (tester) async {
    final controller = HomeController(repository: FakeRepository(), storage: FakeStorage());
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark, home: SettingsScreen(controller: controller)),
    );
    await tester.pumpAndSettle();

    expect(find.text('PLAYLIST'), findsOneWidget);
    expect(find.text('APPLICATION'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.textContaining('Media3 ExoPlayer'), findsNothing);
    expect(find.textContaining('kompatibilitas stream'), findsNothing);
    expect(find.byTooltip('Tambahkan link playlist'), findsOneWidget);

    await tester.tap(find.text('APPLICATION'));
    await tester.pumpAndSettle();
    expect(find.text('Optimize prebuffer'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'User-Agent'), findsOneWidget);
    expect(find.text('Random User-Agent'), findsNothing);

    await tester.tap(find.text('ABOUT'));
    await tester.pumpAndSettle();
    expect(find.text('SitorusTV'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
