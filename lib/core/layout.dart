import 'package:flutter/widgets.dart';

/// The ONE place that decides how the app adapts to screen size and how much space things get.
/// Screens never use raw numbers like 600 or 720: they use [WindowClass] / [ResponsiveGrid] and the spacing tokens below.
///
/// Breakpoints and class names follow Material Design 3 "window size classes":
///   compact  < 600 dp   (phones, portrait)
///   medium   600-839 dp (large phones landscape, small tablets)
///   expanded >= 840 dp  (tablets, laptops)
enum WindowClass { compact, medium, expanded }

const double kMediumBreakpoint = 600;
const double kExpandedBreakpoint = 840;

WindowClass windowClassFor(double width) => width >= kExpandedBreakpoint
    ? WindowClass.expanded
    : width >= kMediumBreakpoint
    ? WindowClass.medium
    : WindowClass.compact;

extension WindowClassContext on BuildContext {
  WindowClass get windowClass => windowClassFor(MediaQuery.sizeOf(this).width);

  /// True on tablets and laptops: navigation moves to a side rail.
  bool get isWide => windowClass != WindowClass.compact;
}

/// Spacing scale (dp). Use these instead of literal numbers.
const double kGapXS = 3;
const double kGapS = 6;
const double kGapM = 10;
const double kGapL = 12;
const double kGapXL = 18;

/// Side padding used on every screen (small, so content covers most of the page).
const double kPagePadding = 12;

/// Lays children out in equal-width columns, choosing the column count from the available width.
/// Phones get [compact] columns, small tablets [medium], big screens [expanded].
class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.compact = 1, this.medium = 2, this.expanded = 3, this.spacing = kGapM});
  final List<Widget> children;
  final int compact, medium, expanded;
  final double spacing;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = switch (windowClassFor(c.maxWidth)) {
        WindowClass.compact => compact,
        WindowClass.medium => medium,
        WindowClass.expanded => expanded,
      };
      final w = (c.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    },
  );
}
