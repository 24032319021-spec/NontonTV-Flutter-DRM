import 'package:flutter/material.dart';

/// The native video only paints. Flutter owns touch input and the controls above
/// it, including when the auto-hiding controls are invisible.
class PlayerInteractionLayer extends StatelessWidget {
  const PlayerInteractionLayer({
    super.key,
    required this.surface,
    required this.controls,
    required this.controlsVisible,
    required this.onInteraction,
    required this.onClose,
    this.status = const SizedBox.shrink(),
    this.onDoubleTap,
    this.onHorizontalDragEnd,
    this.onVerticalDragEnd,
    this.onControlsFocusChanged,
  });

  final Widget surface;
  final Widget controls;
  final Widget status;
  final bool controlsVisible;
  final VoidCallback onInteraction;
  final VoidCallback onClose;
  final VoidCallback? onDoubleTap;
  final GestureDragEndCallback? onHorizontalDragEnd;
  final GestureDragEndCallback? onVerticalDragEnd;
  final ValueChanged<bool>? onControlsFocusChanged;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(child: IgnorePointer(child: surface)),
        Listener(
          behavior: HitTestBehavior.opaque,
          // Pointer-down shows controls immediately, without waiting for the
          // tap/double-tap gesture arena or a native-view callback.
          onPointerDown: (_) => onInteraction(),
          onPointerUp: (_) => onInteraction(),
          child: Focus(
            canRequestFocus: false,
            onFocusChange: onControlsFocusChanged,
            child: GestureDetector(
              key: const ValueKey('player-touch-layer'),
              behavior: HitTestBehavior.opaque,
              onTap: onInteraction,
              onDoubleTap: onDoubleTap,
              onHorizontalDragEnd: onHorizontalDragEnd,
              onVerticalDragEnd: onVerticalDragEnd,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  IgnorePointer(child: status),
                  ExcludeFocus(
                    excluding: !controlsVisible,
                    child: ExcludeSemantics(
                      excluding: !controlsVisible,
                      child: IgnorePointer(
                        ignoring: !controlsVisible,
                        child: AnimatedOpacity(
                          opacity: controlsVisible ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: controls,
                        ),
                      ),
                    ),
                  ),
                  // Close stays outside the auto-hiding overlay.
                  Positioned(
                    top: 10,
                    right: 12,
                    child: SafeArea(
                      bottom: false,
                      child: IconButton.filledTonal(
                        key: const ValueKey('player-close'),
                        tooltip: 'Tutup player',
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xB3202020),
                          foregroundColor: Colors.white,
                          focusColor: const Color(0xB3FE9402),
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
