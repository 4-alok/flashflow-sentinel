import 'package:flutter/gestures.dart';
import 'package:get/get.dart';
import 'dashboard_controller.dart';

/// Horizontal-only pinch-to-zoom state for the spending chart, tracked
/// reactively (scale is Rx) instead of via StatefulWidget/setState.
///
/// Only zoom is handled here — panning is delegated to a real
/// [SingleChildScrollView] (native one-finger horizontal swipe) in the view,
/// since a hand-rolled pointer-tracked pan doesn't give the usual scroll
/// feel (momentum/fling) for free. This controller only reacts to a
/// two-finger pinch to grow/shrink the chart's content width; the scroll
/// view then makes that wider content reachable by dragging.
///
/// Auto-resets whenever the dashboard's period or period offset changes, so
/// navigating to a different day/week/month always starts from a clean view.
class ChartZoomController extends GetxController {
  static const minScale = 1.0;
  static const maxScale = 4.0;

  final scale = minScale.obs;

  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double _pinchStartScale = minScale;

  @override
  void onInit() {
    super.onInit();
    final dashboard = Get.find<DashboardController>();
    ever(dashboard.period, (_) => reset());
    ever(dashboard.periodOffset, (_) => reset());
  }

  void reset() {
    scale.value = minScale;
    _pointers.clear();
    _pinchStartDistance = null;
  }

  void onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartScale = scale.value;
    }
  }

  void onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.position;
    final startDistance = _pinchStartDistance;
    if (_pointers.length != 2 || startDistance == null || startDistance <= 0) {
      return;
    }

    final pts = _pointers.values.toList();
    final distance = (pts[0] - pts[1]).distance;
    scale.value =
        (_pinchStartScale * distance / startDistance).clamp(minScale, maxScale);
  }

  void onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length < 2) _pinchStartDistance = null;
  }
}
