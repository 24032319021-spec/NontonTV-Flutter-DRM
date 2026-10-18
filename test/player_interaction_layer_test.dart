import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nontontv_flutter/features/player/presentation/player_interaction_layer.dart';

// A consuming surface stands in for the native view. These tests exercise the
// Flutter hit-test/gesture boundary; actual Android composition needs a device.
class _Harness extends StatefulWidget {
  const _Harness({super.key});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool visible = false;
  int nativeTouches = 0;
  int closes = 0;
  int plays = 0;
  int swipes = 0;
  Timer? timer;
  final playFocus = FocusNode();

  void showControls() {
    setState(() => visible = true);
    timer?.cancel();
    timer = Timer(const Duration(seconds: 5), () {
      setState(() => visible = false);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    playFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: PlayerInteractionLayer(
          surface: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => nativeTouches++,
            child: const ColoredBox(color: Colors.black),
          ),
          controlsVisible: visible,
          onInteraction: showControls,
          onClose: () => closes++,
          onDoubleTap: () => plays++,
          onHorizontalDragEnd: (_) => swipes++,
          controls: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black26),
            child: Center(child: IconButton(
              tooltip: 'Play',
              focusNode: playFocus,
              onPressed: () => plays++,
              icon: const Icon(Icons.play_arrow),
            )),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('touch reveals hidden controls on pointer-down above a consuming surface', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    expect(find.byTooltip('Play').hitTestable(), findsNothing);
    final touch = await tester.startGesture(const Offset(100, 120));
    await tester.pump();
    expect(key.currentState!.visible, isTrue);
    await touch.up();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
    expect(key.currentState!.nativeTouches, 0);

    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('Play').hitTestable(), findsNothing);
    await tester.tapAt(const Offset(100, 120));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byTooltip('Play').hitTestable(), findsOneWidget);
    expect(key.currentState!.nativeTouches, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('close remains tappable while the other controls are hidden', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    expect(key.currentState!.visible, isFalse);
    expect(find.byTooltip('Tutup player').hitTestable(), findsOneWidget);
    await tester.tap(find.byTooltip('Tutup player'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(key.currentState!.closes, 1);
    expect(key.currentState!.plays, 0);
    expect(key.currentState!.nativeTouches, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('play button and double-tap activate once; swipes remain available', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    await tester.tapAt(const Offset(100, 120));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.byTooltip('Play'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(key.currentState!.plays, 1);
    await tester.tapAt(const Offset(100, 120));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(100, 120));
    await tester.pump(const Duration(milliseconds: 350));
    expect(key.currentState!.plays, 2);
    await tester.flingFrom(const Offset(220, 180), const Offset(220, 0), 1000);
    await tester.pump(const Duration(milliseconds: 350));
    expect(key.currentState!.swipes, 1);
    expect(key.currentState!.nativeTouches, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden controls cannot retain or request keyboard focus', (tester) async {
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(_Harness(key: key));
    key.currentState!.playFocus.requestFocus();
    await tester.pump();
    expect(key.currentState!.playFocus.hasFocus, isFalse);
    await tester.tapAt(const Offset(100, 120));
    await tester.pump(const Duration(milliseconds: 350));
    key.currentState!.playFocus.requestFocus();
    await tester.pump();
    expect(key.currentState!.playFocus.hasFocus, isTrue);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(key.currentState!.playFocus.hasFocus, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
