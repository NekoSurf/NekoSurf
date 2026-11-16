import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

// As CupertinoScrollbar draws it, so every list's scrollbar looks the same.
const Color _kColor = CupertinoDynamicColor.withBrightness(
  color: Color(0x59000000),
  darkColor: Color(0x80FFFFFF),
);
const double _kThickness = 3;
const double _kThicknessWhileDragging = 8;
const Radius _kRadius = Radius.circular(1.5);
const Radius _kRadiusWhileDragging = Radius.circular(4);
const double _kMargin = 3;
const double _kMinLength = 36;
const double _kMinOverscrollLength = 8;
const Duration _kTimeToFade = Duration(milliseconds: 1200);
const Duration _kFadeDuration = Duration(milliseconds: 250);
const Duration _kResizeDuration = Duration(milliseconds: 100);

/// An iOS scrollbar for [child], a vertical scroll view that's given no
/// controller: it shows while the list scrolls, and dragging its thumb
/// scrolls the list fast.
class PageScrollbar extends StatefulWidget {
  const PageScrollbar({super.key, required this.child, this.padding});

  final Widget child;

  /// What the thumb keeps clear of at each end, such as a header or tab bar
  /// over the list; the safe area if not given.
  final EdgeInsets? padding;

  @override
  State<PageScrollbar> createState() => _PageScrollbarState();
}

class _PageScrollbarState extends State<PageScrollbar> {
  // For a list with no controller from its route or tab, such as in a test.
  ScrollController? _own;

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The list scrolls with its route's or tab's controller, which scrolls it
    // to the top when its tab is tapped again; the scrollbar follows the same.
    final ScrollController controller =
        PrimaryScrollController.maybeOf(context) ??
        (_own ??= ScrollController());
    final MediaQueryData media = MediaQuery.of(context);
    final EdgeInsets? padding = widget.padding;
    final Widget bar = CupertinoScrollbar(
      controller: controller,
      // The scrollbar takes its ends from the safe area: the list keeps its own.
      child: MediaQuery(
        data: media,
        child: PrimaryScrollController(
          controller: controller,
          automaticallyInheritForPlatforms: TargetPlatform.values.toSet(),
          child: widget.child,
        ),
      ),
    );
    return padding == null
        ? bar
        : MediaQuery(
            data: media.copyWith(padding: padding),
            child: bar,
          );
  }
}

/// An iOS scrollbar for [child], a [ScrollablePositionedList] of [rowCount]
/// rows, with [positions] and [controller] its listener and controller.
///
/// Such a list measures from the row it last jumped to, not from its top, so
/// this goes by rows instead: the thumb is as far down as the rows on screen
/// are, and dragging it jumps to the row it points at. It keeps clear of the
/// safe area, as [CupertinoScrollbar] does.
class RowScrollbar extends StatefulWidget {
  const RowScrollbar({
    super.key,
    required this.rowCount,
    required this.positions,
    required this.controller,
    required this.child,
    this.endPadding = 0,
  });

  final int rowCount;
  final ItemPositionsListener positions;
  final ItemScrollController controller;
  final Widget child;

  /// The space the list leaves after its last row, which dragging to the end
  /// shows the last row above.
  final double endPadding;

  @override
  State<RowScrollbar> createState() => _RowScrollbarState();
}

/// Where a [RowScrollbar]'s list is, in rows: [top] rows are above the top of
/// the screen, and [shown] rows fit on it.
typedef RowSpan = ({double top, double shown});

/// Where a list showing [positions] is: see [RowSpan]. Null while it shows no
/// rows.
RowSpan? measureRows(Iterable<ItemPosition> positions) {
  double? top;
  int? first;
  double shown = 0;
  for (final ItemPosition position in positions) {
    final double size = position.itemTrailingEdge - position.itemLeadingEdge;
    if (size <= 0 ||
        position.itemTrailingEdge <= 0 ||
        position.itemLeadingEdge >= 1) {
      continue;
    }
    shown +=
        (math.min(position.itemTrailingEdge, 1) -
            math.max(position.itemLeadingEdge, 0)) /
        size;
    if (position.itemLeadingEdge <= 0) {
      top = position.index - position.itemLeadingEdge / size;
    }
    if (first == null || position.index < first) {
      first = position.index;
    }
  }
  if (first == null || shown == 0) {
    return null;
  }
  return (top: top ?? first.toDouble(), shown: shown);
}

class _RowScrollbarState extends State<RowScrollbar>
    with TickerProviderStateMixin {
  final GlobalKey _paintKey = GlobalKey();
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: _kFadeDuration,
  );
  late final AnimationController _thicken = AnimationController(
    vsync: this,
    duration: _kResizeDuration,
  );
  late final ScrollbarPainter _painter = ScrollbarPainter(
    color: const Color(0x00000000),
    fadeoutOpacityAnimation: CurvedAnimation(
      parent: _fade,
      curve: Curves.fastOutSlowIn,
    ),
    thickness: _kThickness,
    radius: _kRadius,
    mainAxisMargin: _kMargin,
    crossAxisMargin: _kMargin,
    minLength: _kMinLength,
    minOverscrollLength: _kMinOverscrollLength,
  );
  Timer? _fadeTimer;
  double _viewport = 0;
  double _pixelRatio = 1;

  /// Where the list was when the thumb was taken, and how far the thumb was
  /// along its track then: the drag goes by these, not by the rows it passes,
  /// whose sizes differ.
  RowSpan? _dragFrom;
  double _dragThumb = 0;
  double _dragStartY = 0;
  int? _jumpedRow;
  double? _jumpedAlignment;

  /// Whether the thumb was taken to the end, to show the last row at the
  /// bottom, however tall the rows before it are.
  bool _toEnd = false;

  @override
  void initState() {
    super.initState();
    widget.positions.itemPositions.addListener(_onPositions);
    _thicken.addListener(_updateThickness);
  }

  @override
  void didUpdateWidget(RowScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positions != widget.positions) {
      oldWidget.positions.itemPositions.removeListener(_onPositions);
      widget.positions.itemPositions.addListener(_onPositions);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _painter
      ..color = CupertinoDynamicColor.resolve(_kColor, context)
      ..textDirection = Directionality.of(context)
      ..padding = MediaQuery.paddingOf(context);
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
  }

  void _updateThickness() {
    final double t = _thicken.value;
    _painter.updateThickness(
      _kThickness + (_kThicknessWhileDragging - _kThickness) * t,
      Radius.lerp(_kRadius, _kRadiusWhileDragging, t)!,
    );
  }

  /// The list as [ScrollMetrics] the painter knows, in pixels: rows count as
  /// the average height of those on screen.
  void _paint(RowSpan span) {
    if (_viewport <= 0) {
      return;
    }
    final double perRow = _viewport / span.shown;
    _painter.update(
      FixedScrollMetrics(
        minScrollExtent: 0,
        maxScrollExtent: math.max(0, widget.rowCount - span.shown) * perRow,
        pixels: span.top * perRow,
        viewportDimension: _viewport,
        axisDirection: AxisDirection.down,
        devicePixelRatio: _pixelRatio,
      ),
      AxisDirection.down,
    );
  }

  void _onPositions() {
    // Until the reader scrolls the list again, as the last jump can land
    // after the thumb is let go.
    if (_jumpedRow != null) {
      _keepEndInPlace();
    }
    if (_dragFrom != null) {
      return;
    }
    final RowSpan? span = measureRows(widget.positions.itemPositions.value);
    if (span != null) {
      _paint(span);
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _jumpedRow = null;
      _toEnd = false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _show();
      if (_dragFrom == null) {
        _hideSoon();
      }
    }
    return false;
  }

  void _show() {
    _fadeTimer?.cancel();
    if (_fade.status != AnimationStatus.forward &&
        _fade.status != AnimationStatus.completed) {
      _fade.forward();
    }
  }

  void _hideSoon() {
    _fadeTimer?.cancel();
    _fadeTimer = Timer(_kTimeToFade, () {
      if (mounted && _dragFrom == null) {
        _fade.reverse();
      }
    });
  }

  bool _onThumb(PointerEvent event) {
    final RenderBox? box =
        _paintKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return false;
    }
    return _painter.hitTestOnlyThumbInteractive(
      box.globalToLocal(event.position),
      event.kind,
    );
  }

  void _onPressStart(DragStartDetails details) {
    final RowSpan? span = measureRows(widget.positions.itemPositions.value);
    if (span == null || widget.rowCount - span.shown <= 0) {
      return;
    }
    _fadeTimer?.cancel();
    _dragFrom = span;
    _dragThumb = _painter.getThumbScrollOffset();
    _dragStartY = details.localPosition.dy;
    _jumpedRow = null;
    _jumpedAlignment = null;
    _toEnd = false;
    _thicken.forward().then<void>((_) => HapticFeedback.mediumImpact());
  }

  void _onPressMove(DragUpdateDetails details) {
    final RowSpan? from = _dragFrom;
    if (from == null) {
      return;
    }
    final double rowsOff = widget.rowCount - from.shown;
    final double perRow = _viewport / from.shown;
    final double maxScroll = rowsOff * perRow;
    final double scroll = _painter
        .getTrackToScroll(_dragThumb + details.localPosition.dy - _dragStartY)
        .clamp(0, maxScroll);
    final double top = scroll / perRow;
    // The thumb follows the finger, while the list goes row by row.
    _paint((top: top, shown: from.shown));

    _toEnd = scroll >= maxScroll;
    if (_toEnd) {
      if (_jumpedRow != widget.rowCount - 1) {
        _jumpToEnd(1 / from.shown);
      }
      return;
    }
    final int row = math.min(top.floor(), widget.rowCount - 1);
    // Part of the row is above the screen, as much as is past its top.
    final double alignment = -(top - row) / from.shown;
    if (row == _jumpedRow &&
        (alignment - (_jumpedAlignment ?? 0)).abs() < 0.02) {
      return;
    }
    _jumpedRow = row;
    _jumpedAlignment = alignment;
    if (widget.controller.isAttached) {
      widget.controller.jumpTo(index: row, alignment: alignment);
    }
  }

  /// Shows the last row at the bottom, taking it to be [size] of the screen
  /// tall until it's laid out.
  void _jumpToEnd(double size) {
    if (_viewport <= 0 || !widget.controller.isAttached) {
      return;
    }
    final double bottom = 1 - widget.endPadding / _viewport;
    _jumpedRow = widget.rowCount - 1;
    _jumpedAlignment = bottom - size;
    widget.controller.jumpTo(
      index: widget.rowCount - 1,
      alignment: bottom - size,
    );
  }

  /// Rows count as the same height while dragging, so near the end, the last
  /// row can come up short of the bottom, leaving space below it, or at the
  /// end, run past it: this puts it at the bottom, once it's laid out.
  void _keepEndInPlace() {
    if (_viewport <= 0) {
      return;
    }
    final ItemPosition? end = widget.positions.itemPositions.value
        .where((ItemPosition position) => position.index == widget.rowCount - 1)
        .firstOrNull;
    if (end == null) {
      return;
    }
    final double bottom = 1 - widget.endPadding / _viewport;
    final double off = end.itemTrailingEdge - bottom;
    if (off.abs() < 0.001 || (off > 0 && !_toEnd)) {
      return;
    }
    _jumpToEnd(end.itemTrailingEdge - end.itemLeadingEdge);
  }

  void _onPressEnd() {
    if (_dragFrom == null) {
      return;
    }
    _dragFrom = null;
    _thicken.reverse();
    HapticFeedback.mediumImpact();
    _onPositions();
    _hideSoon();
  }

  @override
  void dispose() {
    widget.positions.itemPositions.removeListener(_onPositions);
    _fadeTimer?.cancel();
    _fade.dispose();
    _thicken.dispose();
    _painter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _viewport = constraints.maxHeight;
          return RawGestureDetector(
            gestures: <Type, GestureRecognizerFactory>{
              _ThumbPress: GestureRecognizerFactoryWithHandlers<_ThumbPress>(
                () => _ThumbPress(onThumb: _onThumb),
                (_ThumbPress press) => press
                  ..onStart = _onPressStart
                  ..onUpdate = _onPressMove
                  ..onEnd = ((_) => _onPressEnd())
                  ..onCancel = _onPressEnd,
              ),
            },
            child: CustomPaint(
              key: _paintKey,
              foregroundPainter: _painter,
              child: RepaintBoundary(child: widget.child),
            ),
          );
        },
      ),
    );
  }
}

/// A drag that starts on the thumb takes it at once, as on the pages with
/// [CupertinoScrollbar]; anywhere else, the list has the touch.
class _ThumbPress extends VerticalDragGestureRecognizer {
  _ThumbPress({required this.onThumb}) {
    gestureSettings = const DeviceGestureSettings(touchSlop: 0);
    dragStartBehavior = DragStartBehavior.down;
  }

  final bool Function(PointerEvent event) onThumb;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) => false;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      onThumb(event) && super.isPointerAllowed(event);
}
