import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../data/models/campus_map.dart';

class _PanSample {
  const _PanSample(this.point, this.timeMs);

  final Offset point;
  final double timeMs;
}

class _GestureState {
  const _GestureState({
    required this.view,
    this.point,
    this.midpoint,
    this.distance,
  });

  final Rect view;
  final Offset? point;
  final Offset? midpoint;
  final double? distance;
}

class _FocusTarget {
  const _FocusTarget({required this.point, this.box});

  final Offset point;
  final Rect? box;
}

sealed class _CameraMotion {
  const _CameraMotion();
}

final class _InertiaMotion extends _CameraMotion {
  _InertiaMotion({
    required this.start,
    required this.startedMs,
    required this.vx,
    required this.vy,
    required this.durationMs,
  });

  Rect start;
  final double startedMs;
  double vx;
  double vy;
  final double durationMs;
}

final class _FocusMotion extends _CameraMotion {
  const _FocusMotion({
    required this.start,
    required this.target,
    required this.startedMs,
    required this.deadlineMs,
  });

  final Rect start;
  final Rect target;
  final double startedMs;
  final double deadlineMs;
}

class _TapRecord {
  const _TapRecord({required this.timeMs, required this.point, this.placeId});

  final double timeMs;
  final Offset point;
  final String? placeId;
}

/// Native 120Hz-ready camera, pointer gesture, inertia, and focus controller
/// for the campus map canvas.
class CampusMapCameraController extends ChangeNotifier {
  Rect _bounds = const Rect.fromLTWH(0, 0, 1, 1);
  Rect _view = const Rect.fromLTWH(0, 0, 1, 1);
  Rect _base = const Rect.fromLTWH(0, 0, 1, 1);
  Size _viewport = const Size(1, 1);
  double _bottomInset = 0;
  CampusMapView? _initialView;
  bool _isDefaultView = true;
  bool _active = true;
  bool _reducedMotion = false;

  final Map<int, Offset> _pointers = <int, Offset>{};
  _GestureState? _gesture;
  final List<_PanSample> _panSamples = <_PanSample>[];
  bool _moved = false;
  _TapRecord? _lastTap;
  _CameraMotion? _motion;
  _FocusTarget? _focusTarget;

  Rect get bounds => _bounds;
  Rect get view => _view;
  Rect get base => _base;
  Size get viewport => _viewport;
  double get bottomInset => _bottomInset;
  bool get isMoving => _pointers.isNotEmpty || _motion != null;
  bool get hasActiveMotion => _motion != null;
  bool get active => _active;
  bool get isDefaultView => _isDefaultView;

  double get unitsPerPixel => _view.width / math.max(1.0, _viewport.width);

  double get _fillWidth => math.min(
        _bounds.width,
        _bounds.height * _viewport.width / math.max(1.0, _viewport.height),
      );

  CampusMapView get currentCampusView => CampusMapView(
        zoom: _fillWidth / math.max(1e-6, _view.width),
        center: CampusMapPoint(_view.center.dx, _view.center.dy),
      );

  void configure({
    required Rect bounds,
    required CampusMapView initialView,
    required double bottomInset,
    required bool active,
    required bool reducedMotion,
  }) {
    _bounds = bounds;
    _initialView = initialView;
    _bottomInset = math.max(0.0, bottomInset);
    _active = active;
    _reducedMotion = reducedMotion;
    _focusTarget = null;
    _motion = null;
    _pointers.clear();
    _gesture = null;
    _panSamples.clear();
    _lastTap = null;
    _moved = false;
    _applyDefaultView(notify: false);
    notifyListeners();
  }

  void setReducedMotion(bool value) {
    _reducedMotion = value;
  }

  void setActive(bool next) {
    if (_active == next) return;
    _active = next;
    if (!_active) {
      _focusTarget = null;
      _motion = null;
      _pointers.clear();
      _gesture = null;
      _panSamples.clear();
      _lastTap = null;
      _moved = false;
      notifyListeners();
    }
  }

  void setBottomInset(double next, {required double nowMs}) {
    final clamped = math.max(0.0, next);
    if ((clamped - _bottomInset).abs() < 1e-6) return;
    _bottomInset = clamped;
    _updateBase();
    if (_focusTarget != null) {
      _refocus(nowMs);
    } else {
      notifyListeners();
    }
  }

  void setViewportSize(Size next, {required double nowMs, bool notify = true}) {
    final sanitized = Size(
      math.max(1.0, next.width),
      math.max(1.0, next.height),
    );
    if ((sanitized.width - _viewport.width).abs() < 0.5 &&
        (sanitized.height - _viewport.height).abs() < 0.5) {
      return;
    }
    _viewport = sanitized;
    _updateBase();
    if (_isDefaultView && _initialView != null) {
      _applyDefaultView(notify: false);
      if (notify) notifyListeners();
      return;
    }
    final center = _view.center;
    final height = _view.width * _viewport.height / _viewport.width;
    _view = Rect.fromCenter(center: center, width: _view.width, height: height);
    if (_focusTarget != null) {
      _refocus(nowMs, notify: notify);
    } else {
      _motion = null;
      _constrain();
      if (notify) notifyListeners();
    }
    if (_pointers.isNotEmpty) {
      _startGesture(nowMs);
    }
  }

  void focus(Offset point, {Rect? box, required double nowMs}) {
    if (!point.dx.isFinite || !point.dy.isFinite) return;
    _isDefaultView = false;
    _focusTarget = _FocusTarget(point: point, box: box);
    _moveTo(_computeFocusView(), durationMs: 360, nowMs: nowMs);
  }

  void cancelFocus() {
    _focusTarget = null;
    _motion = null;
  }

  void handleBackgrounded() {
    _pointers.clear();
    _gesture = null;
    _panSamples.clear();
    _lastTap = null;
    if (_focusTarget != null) {
      _view = _computeFocusView();
    }
    _motion = null;
    notifyListeners();
  }

  Offset screenToWorld(Offset local, [Rect? box]) {
    final target = box ?? _view;
    return Offset(
      target.left + local.dx / _viewport.width * target.width,
      target.top + local.dy / _viewport.height * target.height,
    );
  }

  Offset worldToScreen(Offset world, [Rect? box]) {
    final target = box ?? _view;
    return Offset(
      (world.dx - target.left) / target.width * _viewport.width,
      (world.dy - target.top) / target.height * _viewport.height,
    );
  }

  void onPointerDown(int pointerId, Offset position, double timeMs) {
    if (!_active) return;
    final interrupted = _motion is _InertiaMotion;
    cancelFocus();
    _isDefaultView = false;
    if (_pointers.isEmpty) _moved = interrupted;
    _pointers[pointerId] = position;
    if (_pointers.length > 1) {
      _moved = true;
      _lastTap = null;
    }
    _startGesture(timeMs);
    notifyListeners();
  }

  void onPointerMove(int pointerId, Offset position, double timeMs) {
    if (!_active || !_pointers.containsKey(pointerId) || _gesture == null) {
      return;
    }
    _pointers[pointerId] = position;
    if (_gesture!.point != null && (position - _gesture!.point!).distance > 3) {
      _moved = true;
    }
    _samplePan(position, timeMs);
    _applyGesture();
    notifyListeners();
  }

  /// Handles pointer up / cancel. Returns the tapped place id (or empty/null)
  /// via [onTap] if this gesture resolved to a single tap.
  void onPointerUp(
    int pointerId,
    Offset position,
    double timeMs, {
    double? nowMs,
    required bool cancelled,
    required String? Function(Offset worldPoint) hitTestPlace,
    required void Function(String? placeId) onSingleTap,
  }) {
    if (!_pointers.containsKey(pointerId)) return;
    final single = _pointers.length == 1;
    if (!cancelled && _gesture != null) {
      _pointers[pointerId] = position;
      if (_gesture!.point != null &&
          (position - _gesture!.point!).distance > 3) {
        _moved = true;
      }
      _samplePan(position, timeMs);
      _applyGesture();
    }
    _pointers.remove(pointerId);

    if (!cancelled && single && _moved && _gesture?.point != null) {
      _startInertia(timeMs, nowMs ?? timeMs);
    }

    if (!cancelled && single && !_moved) {
      final placeId = hitTestPlace(screenToWorld(position));
      final previous = _lastTap;
      if (previous != null &&
          previous.placeId == placeId &&
          timeMs - previous.timeMs < 280 &&
          (previous.point - position).distance < 24) {
        zoom(2.0, position);
        _lastTap = null;
      } else {
        _lastTap = _TapRecord(timeMs: timeMs, point: position, placeId: placeId);
        onSingleTap(placeId);
      }
    }

    _startGesture(timeMs);
    notifyListeners();
  }

  void onWheelZoom(double scrollDeltaY, Offset focalPoint) {
    if (!_active) return;
    cancelFocus();
    _isDefaultView = false;
    final factor = math.exp((-scrollDeltaY * 0.002).clamp(-4.0, 4.0));
    zoom(factor, focalPoint);
  }

  void zoom(double factor, Offset focalPoint) {
    _isDefaultView = false;
    cancelFocus();
    final anchor = screenToWorld(focalPoint);
    final minWidth = math.max(
          _bounds.width,
          _bounds.height * _viewport.width / _viewport.height,
        ) /
        18.0;
    final width = (_view.width / factor).clamp(minWidth, _base.width);
    final height = width * _viewport.height / _viewport.width;
    _view = Rect.fromLTWH(
      anchor.dx - focalPoint.dx / _viewport.width * width,
      anchor.dy - focalPoint.dy / _viewport.height * height,
      width,
      height,
    );
    _constrain();
    notifyListeners();
  }

  /// Advances active inertia or focus animation to [nowMs].
  /// Returns true if more frames are required.
  bool tick(double nowMs) {
    final motion = _motion;
    if (motion == null || !_active) return false;
    switch (motion) {
      case _InertiaMotion():
        final elapsed = (nowMs - motion.startedMs).clamp(0.0, motion.durationMs);
        final decay = math.exp(-elapsed / 240.0);
        final travel = 240.0 * (1.0 - decay);
        final x = motion.start.left + motion.vx * travel;
        final y = motion.start.top + motion.vy * travel;
        _view = Rect.fromLTWH(x, y, motion.start.width, motion.start.height);
        _constrain();
        if ((_view.left - x).abs() > 1e-6) {
          motion.vx = 0;
          motion.start = Rect.fromLTWH(
            _view.left,
            motion.start.top,
            motion.start.width,
            motion.start.height,
          );
        }
        if ((_view.top - y).abs() > 1e-6) {
          motion.vy = 0;
          motion.start = Rect.fromLTWH(
            motion.start.left,
            _view.top,
            motion.start.width,
            motion.start.height,
          );
        }
        if (elapsed >= motion.durationMs ||
            (motion.vx == 0 && motion.vy == 0)) {
          _motion = null;
        }
      case _FocusMotion():
        final span = math.max(1.0, motion.deadlineMs - motion.startedMs);
        final progress = ((nowMs - motion.startedMs) / span).clamp(0.0, 1.0);
        final eased = 1.0 - math.pow(1.0 - progress, 3).toDouble();
        _view = Rect.fromLTWH(
          motion.start.left + (motion.target.left - motion.start.left) * eased,
          motion.start.top + (motion.target.top - motion.start.top) * eased,
          motion.start.width +
              (motion.target.width - motion.start.width) * eased,
          motion.start.height +
              (motion.target.height - motion.start.height) * eased,
        );
        if (progress >= 1.0) {
          _view = motion.target;
          _motion = null;
        }
    }
    notifyListeners();
    return _motion != null;
  }

  void _updateBase() {
    final visibleHeight =
        math.max(_viewport.height * 0.25, _viewport.height - _bottomInset);
    final width = math.max(
      _bounds.width * 1.08,
      _bounds.height * 1.08 * _viewport.width / visibleHeight,
    );
    final height = width * _viewport.height / _viewport.width;
    _base = Rect.fromLTWH(
      _bounds.center.dx - width / 2,
      _bounds.center.dy - height * visibleHeight / _viewport.height / 2,
      width,
      height,
    );
  }

  void _applyDefaultView({required bool notify}) {
    _isDefaultView = true;
    _updateBase();
    final initial = _initialView;
    if (initial == null) {
      _view = _base;
    } else {
      final initialWidth = _fillWidth / initial.zoom;
      final initialHeight = initialWidth * _viewport.height / _viewport.width;
      _view = Rect.fromCenter(
        center: Offset(initial.center.x, initial.center.y),
        width: initialWidth,
        height: initialHeight,
      );
    }
    if (notify) notifyListeners();
  }

  void _constrain() {
    final minWidth = math.max(
          _bounds.width,
          _bounds.height * _viewport.width / _viewport.height,
        ) /
        18.0;
    final maxWidth = math.max(_base.width, _bounds.width * 1.2);
    final width = _view.width.clamp(minWidth, maxWidth);
    final height = width * _viewport.height / _viewport.width;
    final padX = width * 0.35;
    final padY = height * 0.35;
    final centerX =
        _view.center.dx.clamp(_bounds.left - padX, _bounds.right + padX);
    final centerY =
        _view.center.dy.clamp(_bounds.top - padY, _bounds.bottom + padY);
    _view = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: width,
      height: height,
    );
  }

  Rect _computeFocusView() {
    final target = _focusTarget!;
    final ratio = _viewport.width / _viewport.height;
    final visibleHeight =
        math.max(_viewport.height * 0.25, _viewport.height - _bottomInset);
    final minWidth = math.max(_bounds.width, _bounds.height * ratio) / 18.0;
    final maxWidth = math.max(_base.width, _bounds.width * 1.2);
    final box = target.box;
    final width = math
        .max(
          _base.width / 5.0,
          math.max(
            box != null ? box.width * 2.0 : 0.0,
            box != null ? box.height * 2.0 * _viewport.width / visibleHeight : 0.0,
          ),
        )
        .clamp(minWidth, maxWidth);
    final height = width / ratio;
    return Rect.fromLTWH(
      target.point.dx - width / 2,
      target.point.dy - height * visibleHeight / _viewport.height / 2,
      width,
      height,
    );
  }

  void _moveTo(
    Rect target, {
    required double durationMs,
    required double nowMs,
    bool notify = true,
  }) {
    _motion = null;
    if (durationMs <= 0 || _reducedMotion) {
      _view = target;
    } else {
      _motion = _FocusMotion(
        start: _view,
        target: target,
        startedMs: nowMs,
        deadlineMs: nowMs + durationMs,
      );
    }
    if (notify) notifyListeners();
  }

  void _refocus(double nowMs, {bool notify = true}) {
    if (_focusTarget == null) return;
    final current = _motion;
    final remaining = current is _FocusMotion
        ? math.max(0.0, current.deadlineMs - nowMs)
        : 0.0;
    _moveTo(
      _computeFocusView(),
      durationMs: remaining,
      nowMs: nowMs,
      notify: notify,
    );
  }

  void _startGesture(double timeMs) {
    final current = _pointers.values.toList(growable: false);
    _panSamples.clear();
    if (current.length == 1) {
      _panSamples.add(_PanSample(current[0], timeMs));
      _gesture = _GestureState(view: _view, point: current[0]);
    } else if (current.length >= 2) {
      final mid = (current[0] + current[1]) / 2.0;
      final dist = math.max(1.0, (current[0] - current[1]).distance);
      _gesture = _GestureState(view: _view, midpoint: mid, distance: dist);
    } else {
      _gesture = null;
    }
  }

  void _samplePan(Offset point, double timeMs) {
    if (_gesture?.point == null || _pointers.length != 1) return;
    if (_panSamples.isNotEmpty && timeMs < _panSamples.last.timeMs) return;
    if (_panSamples.isNotEmpty && timeMs == _panSamples.last.timeMs) {
      _panSamples.removeLast();
    }
    _panSamples.add(_PanSample(point, timeMs));
    while (_panSamples.length > 2 && timeMs - _panSamples.first.timeMs > 80) {
      _panSamples.removeAt(0);
    }
    if (_panSamples.length > 12) {
      _panSamples.removeAt(0);
    }
  }

  void _applyGesture() {
    final gesture = _gesture;
    if (gesture == null) return;
    final current = _pointers.values.toList(growable: false);
    if (current.length >= 2 &&
        gesture.midpoint != null &&
        gesture.distance != null) {
      final midpoint = (current[0] + current[1]) / 2.0;
      final scale = (current[0] - current[1]).distance / gesture.distance!;
      final anchor = screenToWorld(gesture.midpoint!, gesture.view);
      final minWidth = math.max(
            _bounds.width,
            _bounds.height * _viewport.width / _viewport.height,
          ) /
          18.0;
      final width = (gesture.view.width / math.max(0.1, scale))
          .clamp(minWidth, _base.width);
      final height = width * _viewport.height / _viewport.width;
      _view = Rect.fromLTWH(
        anchor.dx - midpoint.dx / _viewport.width * width,
        anchor.dy - midpoint.dy / _viewport.height * height,
        width,
        height,
      );
      _constrain();
    } else if (current.length == 1 && gesture.point != null && _moved) {
      final delta = current[0] - gesture.point!;
      _view = Rect.fromLTWH(
        gesture.view.left - delta.dx / _viewport.width * gesture.view.width,
        gesture.view.top - delta.dy / _viewport.height * gesture.view.height,
        gesture.view.width,
        gesture.view.height,
      );
      _constrain();
    }
  }

  void _startInertia(double eventTimeMs, double nowMs) {
    if (_reducedMotion) return;
    final samples = _panSamples
        .where((s) => eventTimeMs - s.timeMs <= 80)
        .toList(growable: false);
    if (samples.length < 2) return;
    final first = samples.first;
    final last = samples.last;
    final elapsed = last.timeMs - first.timeMs;
    if (elapsed < 8) return;
    final vx = (last.point.dx - first.point.dx) / elapsed;
    final vy = (last.point.dy - first.point.dy) / elapsed;
    final speed = math.sqrt(vx * vx + vy * vy);
    if (speed < 0.08) return;
    final unit = _view.width / _viewport.width;
    final factor = math.min(1.0, 3.0 / speed) * -unit;
    final duration = math.min(
      1200.0,
      240.0 * math.log(math.min(speed, 3.0) / 0.02),
    );
    _motion = _InertiaMotion(
      start: _view,
      startedMs: nowMs,
      vx: vx * factor,
      vy: vy * factor,
      durationMs: duration,
    );
  }
}
