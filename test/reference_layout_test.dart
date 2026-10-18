import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/core/theme/app_theme.dart';
import 'package:nontontv_flutter/features/channels/domain/channel.dart';
import 'package:nontontv_flutter/features/channels/domain/playlist_result.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_controller.dart';
import 'package:nontontv_flutter/features/channels/presentation/home_screen.dart';

import 'support/fakes.dart';

class _ReferenceRepository extends FakeRepository {
  @override
  Future<PlaylistResult> loadUrlDetailed(String url) async => PlaylistResult(channels: [
    for (var i = 0; i < 12; i++)
      TvChannel(id: '$i', name: 'Channel $i', url: 'https://example.com/$i',
        group: i < 10 ? 'Nasional' : 'Indonesia'),
  ]);
}

void main() {
  for (final density in [1.0, 2.0]) {
    testWidgets('reference has five channels per row at density $density', (tester) async {
      tester.view.physicalSize = const Size(1280, 576);
      tester.view.devicePixelRatio = density;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = HomeController(repository: _ReferenceRepository(), storage: FakeStorage());
      await controller.initialize();
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: HomeScreen(controller: controller)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final first = tester.getCenter(find.text('Channel 0'));
      final fifth = tester.getCenter(find.text('Channel 4'));
      final sixth = tester.getCenter(find.text('Channel 5'));
      expect(fifth.dy, closeTo(first.dy, .1));
      expect((sixth.dy - first.dy) * density, closeTo(232, .1));
      expect(tester.getSize(find.byKey(const ValueKey('category-sidebar'))).width * density,
        closeTo(320, .1));
      expect(find.text('Channel 9'), findsOneWidget);
      expect(find.text('Channel 10'), findsNothing);
      expect(find.text('SEMUA'), findsNothing);
      await tester.tap(find.text('INDONESIA'));
      await tester.pumpAndSettle();
      expect(find.text('Channel 10'), findsOneWidget);
      expect(find.text('Channel 0'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }

  testWidgets('supplied loading art stays until initialization completes', (tester) async {
    final repo = FakeRepository()..pending = Completer<PlaylistResult>();
    final controller = HomeController(repository: repo, storage: FakeStorage());
    final initializing = controller.initialize();
    await tester.pumpWidget(MaterialApp(home: HomeScreen(controller: controller)));
    await tester.pump();
    expect(find.byKey(const ValueKey('loading-screen')), findsOneWidget);
    expect(find.byKey(const ValueKey('menu-background')), findsNothing);
    repo.pending!.complete(sampleResult());
    await initializing;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('loading-screen')), findsNothing);
    expect(find.byKey(const ValueKey('menu-background')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
