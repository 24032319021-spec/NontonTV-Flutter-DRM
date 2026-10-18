import 'package:flutter/widgets.dart';

/// Proportions measured from the supplied 1280 x 576 reference screenshot.
/// Width-based sizing keeps five columns even when Android density changes.
class TvHomeMetrics {
  TvHomeMetrics(Size viewport)
      : landscape = viewport.width >= viewport.height,
        unit = viewport.width >= viewport.height ? viewport.width / 1280 : 1;

  final bool landscape;
  final double unit;
  int get columns => landscape ? 5 : 2;
  double get headerHeight => landscape ? 76 * unit : 64;
  double get sidebarWidth => 320 * unit;
  double get rowHeight => landscape ? 232 * unit : 164;
  double get logoSize => landscape ? 136 * unit : 104;
  double get logoTop => landscape ? 24 * unit : 12;
  double get captionGap => landscape ? 34 * unit : 12;
  double get captionSize => landscape ? 22 * unit : 13;
  double get categoryHeight => landscape ? 60 * unit : 44;
  double get categoryGap => landscape ? 10 * unit : 4;
  double get categoryFontSize => landscape ? 22 * unit : 13;
}
