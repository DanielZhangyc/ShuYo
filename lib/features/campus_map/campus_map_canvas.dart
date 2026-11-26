import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models/campus_map.dart';
import 'campus_map_camera.dart';
import 'campus_map_svg.dart';

class CampusMapCanvasConfiguration {
  const CampusMapCanvasConfiguration({
    required this.campus,
    required this.svg,
    required this.places,
    required this.accent,
    this.selectedPlaceId,
    this.location,
    this.focusPoint,
    this.focusRevision = 0,
    this.bottomInset = 0,
    this.active = true,
    this.onViewChanged,
  });

  final CampusMapCampus campus;
  final String svg;
  final List<CampusMapPlace> places;
  final Color accent;
  final String? selectedPlaceId;
  final Map<String, dynamic>? location;
  final CampusMapPoint? focusPoint;
  final int focusRevision;
  final double bottomInset;
  final bool active;
  final ValueChanged<CampusMapView>? onViewChanged;

  Color get backgroundColor => Color(campus.backgroundArgb);
}

typedef CampusMapCanvasBuilder = Widget Function(
  BuildContext context,
  CampusMapCanvasConfiguration configuration,
  ValueChanged<String> onPlaceTap,
  VoidCallback onMapTap,
);

class _RasterTile {
  const _RasterTile({
    required this.image,
    required this.worldRect,
    required this.pixelsPerUnit,
  });

  final ui.Image image;
  final Rect worldRect;
  final double pixelsPerUnit;

  void dispose() => image.dispose();
}

class _CompiledPlace {
  const _CompiledPlace({
    required this.place,
    required this.paths,
    required this.bounds,
  });

  final CampusMapPlace place;
  final List<Path> paths;
  final Rect? bounds;

  Offset? get center {
    final box = bounds;
    if (box != null) return box.center;
    final pt = place.point;
    if (pt != null && pt.x.isFinite && pt.y.isFinite) {
      return Offset(pt.x, pt.y);
    }
    return null;
  }

  bool get isPointOnly =>
      paths.isEmpty &&
      place.point != null &&
      place.point!.x.isFinite &&
      place.point!.y.isFinite;
}

class _ParsedLocation {
  const _ParsedLocation({required this.point, required this.accuracy});

  final Offset point;
  final double? accuracy;
}

/// Native Flutter 120Hz campus map canvas backed by a compiled SVG scene and
/// two-tier GPU texture cache (full-campus base texture + crisp settled detail
/// texture), avoiding WebView 60Hz frame caps and PlatformView overhead.
class CampusMapCanvas extends StatefulWidget {
  const CampusMapCanvas({
    super.key,
    required this.configuration,
    required this.onPlaceTap,
    required this.onMapTap,
  });

  final CampusMapCanvasConfiguration configuration;
  final ValueChanged<String> onPlaceTap;
  final VoidCallback onMapTap;

  @override
  State<CampusMapCanvas> createState() => _CampusMapCanvasState();
}

class _CampusMapCanvasState extends State<CampusMapCanvas>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _maxBaseTextureDim = 2560;
  static const int _maxDetailTextureDim = 2400;
  static const double _detailOverscanFraction = 0.08;
  static const Duration _detailSettleDelay = Duration(milliseconds: 200);
  static final Map<String, (String, CampusMapSvgDocument)> _documentCache = {};

  final CampusMapCameraController _camera = CampusMapCameraController();
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch()..start();

  CampusMapSvgDocument? _document;
  bool _failed = false;
  String? _loadedCampusId;
  String? _loadedSvg;
  int _focusRevision = -1;
  int _campusGeneration = 0;
  int _detailGeneration = 0;

  Map<String, _CompiledPlace> _placesById = const {};
  List<_CompiledPlace> _hitTestPlaces = const [];
  List<_CompiledPlace> _pointOnlyPlaces = const [];
  _ParsedLocation? _location;

  _RasterTile? _baseTile;
  _RasterTile? _detailTile;
  bool _bakingDetail = false;
  Timer? _detailTimer;
  Timer? _debugReportTimer;
  double _devicePixelRatio = 1.0;
  bool _reducedMotion = false;
  Size _lastViewportSize = Size.zero;
  bool _postFrameSyncScheduled = false;

  double get _nowMs => _clock.elapsedMicroseconds / 1000.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = createTicker(_onTick);
    _camera.addListener(_onCameraChanged);
    _loadCampus(widget.configuration);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    _camera.setReducedMotion(_reducedMotion);
    _schedulePostFrameSync();
  }

  @override
  void didUpdateWidget(covariant CampusMapCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = widget.configuration;
    if (_loadedCampusId != c.campus.id || _loadedSvg != c.svg) {
      _loadCampus(c);
      return;
    }
    if (!identical(oldWidget.configuration.places, c.places)) {
      _compilePlaces(c);
    }
    _syncConfig(c, oldWidget.configuration);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _stopTicker();
      _detailTimer?.cancel();
      _debugReportTimer?.cancel();
      _debugReportTimer = null;
      _camera.handleBackgrounded();
    }
  }

  void _loadCampus(CampusMapCanvasConfiguration c) {
    _campusGeneration++;
    _detailGeneration++;
    _detailTimer?.cancel();
    _debugReportTimer?.cancel();
    _debugReportTimer = null;
    _stopTicker();
    _disposeTiles();

    _loadedCampusId = c.campus.id;
    _loadedSvg = c.svg;
    _focusRevision = -1;

    final bounds = Rect.fromLTWH(
      c.campus.viewBox[0],
      c.campus.viewBox[1],
      c.campus.viewBox[2],
      c.campus.viewBox[3],
    );

    try {
      final cached = _documentCache[c.campus.id];
      final CampusMapSvgDocument doc;
      if (cached != null && cached.$1 == c.svg) {
        doc = cached.$2;
      } else {
        doc = CampusMapSvgDocument.parse(c.svg, fallbackViewBox: bounds);
        _documentCache[c.campus.id] = (c.svg, doc);
      }
      _document = doc;
      _failed = false;
    } catch (_) {
      _document = null;
      _failed = true;
      return;
    }

    _compilePlaces(c);
    _location = _parseLocation(c.location);

    _camera.configure(
      bounds: bounds,
      initialView: c.campus.initialView,
      bottomInset: c.bottomInset,
      active: c.active,
      reducedMotion: _reducedMotion,
    );

    // Apply initial focus request if already present on load.
    _applyFocusIfNeeded(c);
    unawaited(_bakeBaseTile(c, _campusGeneration));
  }

  void _compilePlaces(CampusMapCanvasConfiguration c) {
    final doc = _document;
    if (doc == null) {
      _placesById = const {};
      _hitTestPlaces = const [];
      _pointOnlyPlaces = const [];
      return;
    }
    final byId = <String, _CompiledPlace>{};
    final hitList = <_CompiledPlace>[];
    final pointOnly = <_CompiledPlace>[];
    for (final place in c.places) {
      final paths = <Path>[];
      Rect? bounds;
      for (final fid in place.featureIds) {
        final featurePaths = doc.featurePathsById[fid];
        if (featurePaths != null) paths.addAll(featurePaths);
        final fb = doc.featureBoundsById[fid];
        if (fb != null && !fb.isEmpty) {
          bounds = bounds == null ? fb : bounds.expandToInclude(fb);
        }
      }
      final compiled = _CompiledPlace(
        place: place,
        paths: List.unmodifiable(paths),
        bounds: bounds,
      );
      byId[place.id] = compiled;
      if (compiled.paths.isNotEmpty) {
        hitList.add(compiled);
      } else if (compiled.isPointOnly) {
        pointOnly.add(compiled);
      }
    }
    _placesById = byId;
    // Reverse order so later-painted (topmost) footprints match first.
    _hitTestPlaces = hitList.reversed.toList(growable: false);
    _pointOnlyPlaces = pointOnly;
  }

  void _syncConfig(
    CampusMapCanvasConfiguration c,
    CampusMapCanvasConfiguration old,
  ) {
    if (_document == null) return;
    _camera.setActive(c.active);
    if (!c.active) {
      _stopTicker();
      _detailTimer?.cancel();
      _debugReportTimer?.cancel();
      _debugReportTimer = null;
    }
    if (old.selectedPlaceId != c.selectedPlaceId) {
      _camera.cancelFocus();
    }
    _location = _parseLocation(c.location);
    if ((old.bottomInset - c.bottomInset).abs() > 1e-6) {
      _camera.setBottomInset(c.bottomInset, nowMs: _nowMs);
    }
    _applyFocusIfNeeded(c);
    _syncTicker();
    _scheduleDetailBakeIfNeeded();
  }

  void _applyFocusIfNeeded(CampusMapCanvasConfiguration c) {
    if (_focusRevision == c.focusRevision) return;
    _focusRevision = c.focusRevision;
    final focusPoint = c.focusPoint;
    if (focusPoint != null &&
        focusPoint.x.isFinite &&
        focusPoint.y.isFinite) {
      _camera.focus(Offset(focusPoint.x, focusPoint.y), nowMs: _nowMs);
      _syncTicker();
      return;
    }
    final selectedId = c.selectedPlaceId;
    if (selectedId != null) {
      final compiled = _placesById[selectedId];
      final center = compiled?.center;
      if (center != null) {
        _camera.focus(center, box: compiled?.bounds, nowMs: _nowMs);
        _syncTicker();
      }
    }
  }

  void _onTick(Duration _) {
    final keepGoing = _camera.tick(_nowMs);
    if (!keepGoing) {
      _stopTicker();
      _scheduleDetailBakeIfNeeded();
    }
  }

  void _syncTicker() {
    if (_camera.hasActiveMotion && _camera.active) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _stopTicker();
    }
  }

  void _stopTicker() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onCameraChanged() {
    _syncTicker();
    if (_camera.isMoving) {
      if (_detailTimer != null || _bakingDetail) {
        _detailTimer?.cancel();
        _detailTimer = null;
        _detailGeneration++;
      }
    } else {
      _scheduleDetailBakeIfNeeded();
    }
    _scheduleDebugViewportReport();
  }

  void _scheduleDebugViewportReport() {
    final callback = widget.configuration.onViewChanged;
    if (callback == null || !widget.configuration.active || _document == null) {
      return;
    }
    if (_debugReportTimer != null) return;
    _debugReportTimer = Timer(const Duration(milliseconds: 100), () {
      _debugReportTimer = null;
      if (!mounted || !widget.configuration.active) return;
      widget.configuration.onViewChanged?.call(_camera.currentCampusView);
    });
  }

  Future<void> _bakeBaseTile(
    CampusMapCanvasConfiguration c,
    int generation,
  ) async {
    final doc = _document;
    if (doc == null) return;
    final bounds = _camera.bounds;
    final aspect = bounds.width / math.max(1e-6, bounds.height);
    final int pixelW;
    final int pixelH;
    if (aspect >= 1.0) {
      pixelW = _maxBaseTextureDim;
      pixelH = math.max(1, (_maxBaseTextureDim / aspect).round());
    } else {
      pixelH = _maxBaseTextureDim;
      pixelW = math.max(1, (_maxBaseTextureDim * aspect).round());
    }
    try {
      final image = await doc.rasterize(
        worldRegion: bounds,
        pixelWidth: pixelW,
        pixelHeight: pixelH,
        backgroundColor: c.backgroundColor,
      );
      if (!mounted || generation != _campusGeneration) {
        image.dispose();
        return;
      }
      final tile = _RasterTile(
        image: image,
        worldRect: bounds,
        pixelsPerUnit: pixelW / bounds.width,
      );
      final oldBase = _baseTile;
      setState(() => _baseTile = tile);
      oldBase?.dispose();
      _scheduleDetailBakeIfNeeded();
    } catch (_) {
      // Fall back cleanly to direct vector painting if image baking fails.
    }
  }

  void _scheduleDetailBakeIfNeeded() {
    _detailTimer?.cancel();
    if (!mounted ||
        _document == null ||
        !widget.configuration.active ||
        _camera.isMoving ||
        _camera.viewport.width <= 1 ||
        _camera.viewport.height <= 1) {
      return;
    }
    final targetPpu =
        (_camera.viewport.width * _devicePixelRatio) / _camera.view.width;
    final baseTile = _baseTile;
    if (baseTile != null && targetPpu <= baseTile.pixelsPerUnit * 1.2) {
      // Defer dropping an old detail tile until settled so rapid pinch-out
      // never triggers synchronous setState mid-interaction.
      if (_detailTile != null) {
        _detailTimer = Timer(_detailSettleDelay, () {
          _detailTimer = null;
          if (!mounted || _camera.isMoving || !widget.configuration.active) {
            return;
          }
          final old = _detailTile;
          if (old == null) return;
          setState(() => _detailTile = null);
          old.dispose();
        });
      }
      return;
    }
    final desired = _desiredDetailRect();
    if (desired.width <= 1e-3 || desired.height <= 1e-3) return;
    final desiredPpu = _effectiveDetailPpu(desired, targetPpu);
    final detail = _detailTile;
    if (detail != null &&
        _rectContainsWithEps(detail.worldRect, _camera.view)) {
      final ratio = desiredPpu / detail.pixelsPerUnit;
      if (ratio >= 0.85 && ratio <= 1.15) return;
    }
    _detailTimer = Timer(_detailSettleDelay, () {
      _detailTimer = null;
      if (!mounted || _camera.isMoving || !widget.configuration.active) return;
      unawaited(_bakeDetailTile(_campusGeneration, ++_detailGeneration));
    });
  }

  Rect _desiredDetailRect() {
    final view = _camera.view;
    final bounds = _camera.bounds;
    final padW = view.width * _detailOverscanFraction;
    final padH = view.height * _detailOverscanFraction;
    return Rect.fromLTRB(
      math.max(bounds.left, view.left - padW),
      math.max(bounds.top, view.top - padH),
      math.min(bounds.right, view.right + padW),
      math.min(bounds.bottom, view.bottom + padH),
    );
  }

  double _effectiveDetailPpu(Rect desired, double screenPpu) {
    final rawW = desired.width * screenPpu;
    final rawH = desired.height * screenPpu;
    final maxDim = math.max(rawW, rawH);
    if (maxDim <= _maxDetailTextureDim) return screenPpu;
    return screenPpu * (_maxDetailTextureDim / maxDim);
  }

  Future<void> _bakeDetailTile(int campusGen, int detailGen) async {
    if (_bakingDetail) return;
    final doc = _document;
    if (doc == null) return;
    _bakingDetail = true;
    try {
      final view = _camera.view;
      final desired = _desiredDetailRect();
      if (desired.width <= 1e-3 || desired.height <= 1e-3) return;

      final screenPpu =
          (_camera.viewport.width * _devicePixelRatio) / view.width;
      final ppu = _effectiveDetailPpu(desired, screenPpu);
      final pixelW = math.max(1, (desired.width * ppu).round());
      final pixelH = math.max(1, (desired.height * ppu).round());

      final image = await doc.rasterize(
        worldRegion: desired,
        pixelWidth: pixelW,
        pixelHeight: pixelH,
        backgroundColor: widget.configuration.backgroundColor,
      );
      if (!mounted ||
          campusGen != _campusGeneration ||
          detailGen != _detailGeneration) {
        image.dispose();
        return;
      }
      final tile = _RasterTile(
        image: image,
        worldRect: desired,
        pixelsPerUnit: pixelW / desired.width,
      );
      final old = _detailTile;
      setState(() => _detailTile = tile);
      old?.dispose();
    } catch (_) {
      // Keep base texture on any transient raster error.
    } finally {
      _bakingDetail = false;
    }
  }

  String? _hitTestPlace(Offset worldPoint) {
    final pinHitRadiusWorld = 14.0 * _camera.unitsPerPixel;
    for (final compiled in _pointOnlyPlaces) {
      final center = compiled.center;
      if (center != null && (center - worldPoint).distance <= pinHitRadiusWorld) {
        return compiled.place.id;
      }
    }
    for (final compiled in _hitTestPlaces) {
      final box = compiled.bounds;
      if (box == null || !box.contains(worldPoint)) continue;
      for (final path in compiled.paths) {
        if (path.contains(worldPoint)) {
          return compiled.place.id;
        }
      }
    }
    return null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_document == null || !widget.configuration.active) return;
    _camera.onPointerDown(
      event.pointer,
      event.localPosition,
      event.timeStamp.inMicroseconds / 1000.0,
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_document == null || !widget.configuration.active) return;
    _camera.onPointerMove(
      event.pointer,
      event.localPosition,
      event.timeStamp.inMicroseconds / 1000.0,
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_document == null || !widget.configuration.active) return;
    _camera.onPointerUp(
      event.pointer,
      event.localPosition,
      event.timeStamp.inMicroseconds / 1000.0,
      nowMs: _nowMs,
      cancelled: false,
      hitTestPlace: _hitTestPlace,
      onSingleTap: (placeId) {
        if (!widget.configuration.active) return;
        if (placeId != null) {
          widget.onPlaceTap(placeId);
        } else {
          widget.onMapTap();
        }
      },
    );
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (_document == null) return;
    _camera.onPointerUp(
      event.pointer,
      event.localPosition,
      event.timeStamp.inMicroseconds / 1000.0,
      nowMs: _nowMs,
      cancelled: true,
      hitTestPlace: (_) => null,
      onSingleTap: (_) {},
    );
  }

  void _schedulePostFrameSync() {
    if (_postFrameSyncScheduled) return;
    _postFrameSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _postFrameSyncScheduled = false;
      if (!mounted) return;
      _syncTicker();
      _scheduleDetailBakeIfNeeded();
    });
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_document == null || !widget.configuration.active) return;
    if (event is PointerScrollEvent) {
      _camera.onWheelZoom(event.scrollDelta.dy, event.localPosition);
    } else if (event is PointerScaleEvent) {
      _camera.zoom(event.scale, event.localPosition);
    }
  }

  void _disposeTiles() {
    _baseTile?.dispose();
    _baseTile = null;
    _detailTile?.dispose();
    _detailTile = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detailTimer?.cancel();
    _debugReportTimer?.cancel();
    _ticker.dispose();
    _camera.removeListener(_onCameraChanged);
    _camera.dispose();
    _disposeTiles();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 36),
            const SizedBox(height: 12),
            const Text('地图画布加载失败'),
            TextButton(
              onPressed: () {
                setState(() => _loadCampus(widget.configuration));
              },
              child: const Text('重新加载'),
            ),
          ],
        ),
      );
    }
    final c = widget.configuration;
    final selectedCompiled =
        c.selectedPlaceId == null ? null : _placesById[c.selectedPlaceId!];
    return Semantics(
      label: '${c.campus.name}地图，支持双指缩放与拖动，也可通过搜索查找地点',
      child: ClipRect(
        child: ColoredBox(
          color: c.backgroundColor,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(
                constraints.maxWidth.isFinite ? constraints.maxWidth : 1,
                constraints.maxHeight.isFinite ? constraints.maxHeight : 1,
              );
              if ((size.width - _lastViewportSize.width).abs() >= 0.5 ||
                  (size.height - _lastViewportSize.height).abs() >= 0.5) {
                _lastViewportSize = size;
                _camera.setViewportSize(size, nowMs: _nowMs, notify: false);
                _schedulePostFrameSync();
              }
              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                onPointerCancel: _handlePointerCancel,
                onPointerSignal: _handlePointerSignal,
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: size,
                    isComplex: false,
                    willChange: true,
                    painter: _CampusMapPainter(
                      camera: _camera,
                      document: _document,
                      baseTile: _baseTile,
                      detailTile: _detailTile,
                      backgroundColor: c.backgroundColor,
                      accent: c.accent,
                      selectedPlace: selectedCompiled,
                      pointOnlyPlaces: _pointOnlyPlaces,
                      location: _location,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CampusMapPainter extends CustomPainter {
  _CampusMapPainter({
    required this.camera,
    required this.document,
    required this.baseTile,
    required this.detailTile,
    required this.backgroundColor,
    required this.accent,
    required this.selectedPlace,
    required this.pointOnlyPlaces,
    required this.location,
  }) : super(repaint: camera);

  final CampusMapCameraController camera;
  final CampusMapSvgDocument? document;
  final _RasterTile? baseTile;
  final _RasterTile? detailTile;
  final Color backgroundColor;
  final Color accent;
  final _CompiledPlace? selectedPlace;
  final List<_CompiledPlace> pointOnlyPlaces;
  final _ParsedLocation? location;

  @override
  void paint(Canvas canvas, Size size) {
    final doc = document;
    if (doc == null || size.isEmpty) return;

    final view = camera.view;
    if (view.width <= 0 || view.height <= 0) return;
    final scaleX = size.width / view.width;
    final scaleY = size.height / view.height;

    canvas.save();
    canvas.scale(scaleX, scaleY);
    canvas.translate(-view.left, -view.top);

    final base = baseTile;
    final detail = detailTile;
    final imagePaint = Paint()..filterQuality = FilterQuality.medium;

    void drawVisibleTile(_RasterTile tile) {
      final visible = view.intersect(tile.worldRect);
      if (visible.width <= 0 || visible.height <= 0) return;
      final sx = tile.image.width / tile.worldRect.width;
      final sy = tile.image.height / tile.worldRect.height;
      final src = Rect.fromLTRB(
        (visible.left - tile.worldRect.left) * sx,
        (visible.top - tile.worldRect.top) * sy,
        (visible.right - tile.worldRect.left) * sx,
        (visible.bottom - tile.worldRect.top) * sy,
      );
      canvas.drawImageRect(tile.image, src, visible, imagePaint);
    }

    if (detail != null && _rectContainsWithEps(detail.worldRect, view)) {
      // Detail texture fully covers the viewport; skip base texture to avoid
      // 2x full-screen GPU overdraw during panning and zooming.
      drawVisibleTile(detail);
    } else if (base != null) {
      drawVisibleTile(base);
      if (detail != null && detail.worldRect.overlaps(view)) {
        drawVisibleTile(detail);
      }
    } else {
      // Synchronous vector fallback for the first frame before GPU base tile finishes.
      doc.paint(canvas, cullRect: view);
    }

    final unit = view.width / size.width;

    // 1. Selected building polygon highlight.
    final selected = selectedPlace;
    if (selected != null && selected.paths.isNotEmpty) {
      final fillPaint = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = accent.withValues(alpha: 0x70 / 255.0);
      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..color = accent
        ..strokeWidth = 2.0 * unit
        ..strokeJoin = StrokeJoin.round;
      for (final path in selected.paths) {
        canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
      }
    }

    // 2. Point-only place pins + selected pin fallback.
    if (pointOnlyPlaces.isNotEmpty ||
        (selected != null && selected.paths.isEmpty && selected.center != null)) {
      final pinFill = Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = accent;
      final pinStroke = Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..color = const Color(0xffffffff)
        ..strokeWidth = 2.0 * unit;
      for (final compiled in pointOnlyPlaces) {
        final center = compiled.center;
        if (center == null) continue;
        final radius =
            unit * (compiled.place.id == selected?.place.id ? 7.0 : 4.0);
        canvas.drawCircle(center, radius, pinFill);
        canvas.drawCircle(center, radius, pinStroke);
      }
      if (selected != null && selected.paths.isEmpty) {
        final center = selected.center;
        if (center != null && !selected.isPointOnly) {
          final radius = unit * 7.0;
          canvas.drawCircle(center, radius, pinFill);
          canvas.drawCircle(center, radius, pinStroke);
        }
      }
    }

    // 3. User location accuracy ring + blue dot.
    final loc = location;
    if (loc != null) {
      const blue = Color(0xff2678f2);
      final accuracy = loc.accuracy;
      if (accuracy != null && accuracy > 0) {
        final radius = math.min(accuracy, camera.bounds.width);
        canvas.drawCircle(
          loc.point,
          radius,
          Paint()
            ..style = PaintingStyle.fill
            ..isAntiAlias = true
            ..color = blue.withValues(alpha: 0.12),
        );
        canvas.drawCircle(
          loc.point,
          radius,
          Paint()
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true
            ..color = blue.withValues(alpha: 0.30)
            ..strokeWidth = 1.0 * unit,
        );
      }
      final dotRadius = 6.0 * unit;
      canvas.drawCircle(
        loc.point,
        dotRadius,
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = blue,
      );
      canvas.drawCircle(
        loc.point,
        dotRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true
          ..color = const Color(0xffffffff)
          ..strokeWidth = 3.0 * unit,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CampusMapPainter oldDelegate) =>
      oldDelegate.document != document ||
      oldDelegate.baseTile != baseTile ||
      oldDelegate.detailTile != detailTile ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.accent != accent ||
      oldDelegate.selectedPlace?.place.id != selectedPlace?.place.id ||
      oldDelegate.location?.point != location?.point ||
      oldDelegate.location?.accuracy != location?.accuracy ||
      oldDelegate.pointOnlyPlaces.length != pointOnlyPlaces.length;
}

_ParsedLocation? _parseLocation(Map<String, dynamic>? raw) {
  if (raw == null) return null;
  final x = raw['x'];
  final y = raw['y'];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) return null;
  final acc = raw['accuracy'];
  final accuracy =
      (acc is num && acc.isFinite && acc > 0) ? acc.toDouble() : null;
  return _ParsedLocation(
    point: Offset(x.toDouble(), y.toDouble()),
    accuracy: accuracy,
  );
}

bool _rectContainsWithEps(Rect outer, Rect inner) {
  const eps = 1e-4;
  return inner.left >= outer.left - eps &&
      inner.top >= outer.top - eps &&
      inner.right <= outer.right + eps &&
      inner.bottom <= outer.bottom + eps;
}
