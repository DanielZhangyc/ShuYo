import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Compiled offline SVG campus map scene ready for fast GPU painting and
/// exact world-coordinate hit-testing.
class CampusMapSvgDocument {
  CampusMapSvgDocument._({
    required this.viewBox,
    required List<_SvgDrawOp> drawOps,
    required this.featurePathsById,
    required this.featureBoundsById,
  }) : _drawOps = drawOps;

  final Rect viewBox;
  final List<_SvgDrawOp> _drawOps;
  final Map<String, List<Path>> featurePathsById;
  final Map<String, Rect> featureBoundsById;

  int get drawOpCount => _drawOps.length;

  static const double _textLayoutScale = 4.0;

  /// Parses an offline campus SVG document into an immutable scene graph.
  /// Throws [FormatException] when the document is not valid SVG.
  factory CampusMapSvgDocument.parse(String source, {Rect? fallbackViewBox}) {
    final root = _XmlParser(source).parseRoot();
    if (root == null || root.name != 'svg') {
      throw const FormatException('Invalid SVG root element');
    }
    final viewBox = _parseViewBox(root.attributes['viewBox']) ??
        fallbackViewBox ??
        const Rect.fromLTWH(0, 0, 1, 1);
    final cssRules = <String, Map<String, String>>{};
    _collectCssRules(root, cssRules);

    final drawOps = <_SvgDrawOp>[];
    final featurePathsById = <String, List<Path>>{};
    final featureBoundsById = <String, Rect>{};

    void recordFeaturePath(List<String> ancestorIds, Path path) {
      if (ancestorIds.isEmpty) return;
      final bounds = path.getBounds();
      for (final id in ancestorIds) {
        (featurePathsById[id] ??= <Path>[]).add(path);
        if (!bounds.isEmpty) {
          final existing = featureBoundsById[id];
          featureBoundsById[id] =
              existing == null ? bounds : existing.expandToInclude(bounds);
        }
      }
    }

    void walk(
      _XmlElement element,
      _SvgStyle inherited,
      Matrix4 parentTransform,
      List<String> ancestorIds,
      bool preserveSpace,
    ) {
      // Defence in depth for offline assets.
      switch (element.name) {
        case 'script':
        case 'foreignObject':
        case 'image':
        case 'defs':
        case 'style':
        case 'title':
        case 'desc':
        case 'metadata':
          return;
      }

      final style = _resolveStyle(element, inherited, cssRules);
      final localTransform = _parseTransform(element.attributes['transform']);
      final worldTransform = localTransform == null
          ? parentTransform
          : parentTransform.multiplied(localTransform);
      final id = element.attributes['id'];
      final nextIds = (id != null && id.isNotEmpty && element.name != 'svg')
          ? <String>[...ancestorIds, id]
          : ancestorIds;
      final xmlSpace = element.attributes['xml:space'];
      final nextPreserve =
          xmlSpace == null ? preserveSpace : xmlSpace == 'preserve';

      switch (element.name) {
        case 'path':
          final d = element.attributes['d'];
          if (d != null && d.isNotEmpty) {
            final path = _parsePathData(d);
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'polygon':
          final pts = _parsePoints(element.attributes['points']);
          if (pts.length >= 2) {
            final path = Path()..addPolygon(pts, true);
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'polyline':
          final pts = _parsePoints(element.attributes['points']);
          if (pts.length >= 2) {
            final path = Path()..addPolygon(pts, false);
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'rect':
          final w = _parseLength(element.attributes['width']) ?? 0;
          final h = _parseLength(element.attributes['height']) ?? 0;
          if (w > 0 && h > 0) {
            final x = _parseLength(element.attributes['x']) ?? 0;
            final y = _parseLength(element.attributes['y']) ?? 0;
            var rx = _parseLength(element.attributes['rx']);
            var ry = _parseLength(element.attributes['ry']);
            rx ??= ry ?? 0;
            ry ??= rx;
            final rect = Rect.fromLTWH(x, y, w, h);
            final path = Path();
            if (rx > 0 || ry > 0) {
              path.addRRect(RRect.fromRectXY(
                rect,
                rx.clamp(0, w / 2),
                ry.clamp(0, h / 2),
              ));
            } else {
              path.addRect(rect);
            }
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'line':
          final x1 = _parseLength(element.attributes['x1']) ?? 0;
          final y1 = _parseLength(element.attributes['y1']) ?? 0;
          final x2 = _parseLength(element.attributes['x2']) ?? 0;
          final y2 = _parseLength(element.attributes['y2']) ?? 0;
          final path = Path()
            ..moveTo(x1, y1)
            ..lineTo(x2, y2);
          _emitShape(path, style, worldTransform, nextIds, drawOps,
              recordFeaturePath);
        case 'circle':
          final r = _parseLength(element.attributes['r']) ?? 0;
          if (r > 0) {
            final cx = _parseLength(element.attributes['cx']) ?? 0;
            final cy = _parseLength(element.attributes['cy']) ?? 0;
            final path = Path()
              ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'ellipse':
          final rx = _parseLength(element.attributes['rx']) ?? 0;
          final ry = _parseLength(element.attributes['ry']) ?? 0;
          if (rx > 0 && ry > 0) {
            final cx = _parseLength(element.attributes['cx']) ?? 0;
            final cy = _parseLength(element.attributes['cy']) ?? 0;
            final path = Path()
              ..addOval(Rect.fromCenter(
                  center: Offset(cx, cy), width: rx * 2, height: ry * 2));
            _emitShape(path, style, worldTransform, nextIds, drawOps,
                recordFeaturePath);
          }
        case 'text':
          _emitText(element, style, worldTransform, nextPreserve, drawOps);
        default:
          for (final child in element.children) {
            if (child is _XmlElement) {
              walk(child, style, worldTransform, nextIds, nextPreserve);
            }
          }
      }
    }

    walk(root, _SvgStyle.initial, Matrix4.identity(), const <String>[], false);

    return CampusMapSvgDocument._(
      viewBox: viewBox,
      drawOps: List.unmodifiable(drawOps),
      featurePathsById: {
        for (final entry in featurePathsById.entries)
          entry.key: List.unmodifiable(entry.value),
      },
      featureBoundsById: Map.unmodifiable(featureBoundsById),
    );
  }

  /// Paints the SVG document in world coordinates onto [canvas].
  /// When [cullRect] is provided, elements whose bounding boxes do not
  /// intersect [cullRect] are skipped.
  void paint(Canvas canvas, {Rect? cullRect}) {
    if (cullRect == null) {
      for (final op in _drawOps) {
        op.paint(canvas);
      }
      return;
    }
    for (final op in _drawOps) {
      if (op.intersects(cullRect)) {
        op.paint(canvas);
      }
    }
  }

  /// Renders [worldRegion] into a GPU [ui.Image] of dimensions [pixelWidth] x
  /// [pixelHeight], filled with [backgroundColor].
  Future<ui.Image> rasterize({
    required Rect worldRegion,
    required int pixelWidth,
    required int pixelHeight,
    required Color backgroundColor,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, pixelWidth.toDouble(), pixelHeight.toDouble()),
      Paint()..color = backgroundColor,
    );
    final sx = pixelWidth / worldRegion.width;
    final sy = pixelHeight / worldRegion.height;
    canvas.scale(sx, sy);
    canvas.translate(-worldRegion.left, -worldRegion.top);
    paint(canvas, cullRect: worldRegion);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(pixelWidth, pixelHeight);
    } finally {
      picture.dispose();
    }
  }

  static void _emitShape(
    Path rawPath,
    _SvgStyle style,
    Matrix4 worldTransform,
    List<String> ancestorIds,
    List<_SvgDrawOp> drawOps,
    void Function(List<String>, Path) recordFeaturePath,
  ) {
    rawPath.fillType = style.fillRule;
    final path = _isIdentity(worldTransform)
        ? rawPath
        : rawPath.transform(worldTransform.storage);
    path.fillType = style.fillRule;

    recordFeaturePath(ancestorIds, path);

    final opacity = style.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) return;

    if (style.fill != null) {
      final alpha = (style.fillOpacity * opacity).clamp(0.0, 1.0);
      if (alpha > 0) {
        final paint = Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = style.fill!.withValues(
            alpha: (style.fill!.a * alpha).clamp(0.0, 1.0),
          );
        drawOps.add(_PathDrawOp(path, paint));
      }
    }

    if (style.stroke != null && style.strokeWidth > 0) {
      final alpha = (style.strokeOpacity * opacity).clamp(0.0, 1.0);
      if (alpha > 0) {
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..isAntiAlias = true
          ..color = style.stroke!.withValues(
            alpha: (style.stroke!.a * alpha).clamp(0.0, 1.0),
          )
          ..strokeWidth = style.strokeWidth
          ..strokeCap = style.strokeCap
          ..strokeJoin = style.strokeJoin
          ..strokeMiterLimit = style.strokeMiterLimit;
        final strokePath =
            (style.dashArray != null && style.dashArray!.isNotEmpty)
                ? _dashPath(path, style.dashArray!)
                : path;
        drawOps.add(_PathDrawOp(strokePath, paint));
      }
    }
  }

  static void _emitText(
    _XmlElement element,
    _SvgStyle style,
    Matrix4 worldTransform,
    bool preserveSpace,
    List<_SvgDrawOp> drawOps,
  ) {
    final opacity = style.opacity.clamp(0.0, 1.0);
    if (style.fill == null || opacity <= 0) return;
    final alpha = (style.fillOpacity * opacity).clamp(0.0, 1.0);
    if (alpha <= 0) return;

    final baseX = _parseLength(element.attributes['x']) ?? 0;
    final baseY = _parseLength(element.attributes['y']) ?? 0;

    // Handle either direct text content or child <tspan> segments.
    final spans = element.children.whereType<_XmlElement>().where(
          (child) => child.name == 'tspan',
        );
    if (spans.isEmpty) {
      final text = _normalizeSvgText(element.textContent, preserveSpace);
      if (text.isEmpty) return;
      drawOps.add(_TextDrawOp(
        text: text,
        x: baseX,
        y: baseY,
        transform: worldTransform,
        color: style.fill!.withValues(
          alpha: (style.fill!.a * alpha).clamp(0.0, 1.0),
        ),
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
      ));
      return;
    }

    for (final span in spans) {
      final spanPreserve = span.attributes['xml:space'] == null
          ? preserveSpace
          : span.attributes['xml:space'] == 'preserve';
      final text = _normalizeSvgText(span.textContent, spanPreserve);
      if (text.isEmpty) continue;
      final sx = _parseLength(span.attributes['x']) ?? baseX;
      final sy = _parseLength(span.attributes['y']) ?? baseY;
      drawOps.add(_TextDrawOp(
        text: text,
        x: sx,
        y: sy,
        transform: worldTransform,
        color: style.fill!.withValues(
          alpha: (style.fill!.a * alpha).clamp(0.0, 1.0),
        ),
        fontSize: style.fontSize,
        fontWeight: style.fontWeight,
      ));
    }
  }
}

sealed class _SvgDrawOp {
  bool intersects(Rect cullRect);
  void paint(Canvas canvas);
}

final class _PathDrawOp extends _SvgDrawOp {
  _PathDrawOp(this.path, this.paintObj)
      : bounds = paintObj.style == PaintingStyle.stroke
            ? path.getBounds().inflate(paintObj.strokeWidth)
            : path.getBounds();

  final Path path;
  final Paint paintObj;
  final Rect bounds;

  @override
  bool intersects(Rect cullRect) => bounds.overlaps(cullRect);

  @override
  void paint(Canvas canvas) {
    canvas.drawPath(path, paintObj);
  }
}

final class _TextDrawOp extends _SvgDrawOp {
  _TextDrawOp({
    required this.text,
    required this.x,
    required this.y,
    required this.transform,
    required this.color,
    required this.fontSize,
    required this.fontWeight,
  });

  final String text;
  final double x;
  final double y;
  final Matrix4 transform;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;

  TextPainter? _painter;
  double _baseline = 0;
  Rect? _worldBounds;

  TextPainter _ensurePainter() {
    final existing = _painter;
    if (existing != null) return existing;
    const scale = CampusMapSvgDocument._textLayoutScale;
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize * scale,
          fontWeight: fontWeight,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic) /
            scale;
    final localRect = Rect.fromLTWH(
      x,
      y - _baseline,
      painter.width / scale,
      painter.height / scale,
    );
    _worldBounds = _isIdentity(transform)
        ? localRect
        : MatrixUtils.transformRect(transform, localRect);
    return _painter = painter;
  }

  @override
  bool intersects(Rect cullRect) {
    final bounds = _worldBounds;
    if (bounds != null) return bounds.overlaps(cullRect);
    // Cheap approximate anchor check before laying out offscreen labels.
    final approx = Rect.fromCenter(
      center: MatrixUtils.transformPoint(transform, Offset(x, y)),
      width: fontSize * (text.length + 2),
      height: fontSize * 3,
    );
    return approx.overlaps(cullRect);
  }

  @override
  void paint(Canvas canvas) {
    final painter = _ensurePainter();
    const scale = CampusMapSvgDocument._textLayoutScale;
    canvas.save();
    if (!_isIdentity(transform)) {
      canvas.transform(transform.storage);
    }
    canvas.translate(x, y - _baseline);
    canvas.scale(1 / scale, 1 / scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }
}

class _SvgStyle {
  const _SvgStyle({
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    required this.strokeCap,
    required this.strokeJoin,
    required this.strokeMiterLimit,
    required this.dashArray,
    required this.fillOpacity,
    required this.strokeOpacity,
    required this.opacity,
    required this.fillRule,
    required this.fontSize,
    required this.fontWeight,
  });

  static const initial = _SvgStyle(
    fill: Color(0xff000000),
    stroke: null,
    strokeWidth: 1.0,
    strokeCap: StrokeCap.butt,
    strokeJoin: StrokeJoin.miter,
    strokeMiterLimit: 4.0,
    dashArray: null,
    fillOpacity: 1.0,
    strokeOpacity: 1.0,
    opacity: 1.0,
    fillRule: PathFillType.nonZero,
    fontSize: 12.0,
    fontWeight: FontWeight.normal,
  );

  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final StrokeCap strokeCap;
  final StrokeJoin strokeJoin;
  final double strokeMiterLimit;
  final List<double>? dashArray;
  final double fillOpacity;
  final double strokeOpacity;
  final double opacity;
  final PathFillType fillRule;
  final double fontSize;
  final FontWeight fontWeight;
}

void _collectCssRules(
  _XmlElement element,
  Map<String, Map<String, String>> out,
) {
  if (element.name == 'style') {
    final css = element.textContent.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    for (final match in RegExp(r'([^{}]+)\{([^{}]+)\}').allMatches(css)) {
      final selectors = match
          .group(1)!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.startsWith('.'));
      final decls = _parseDeclarations(match.group(2)!);
      if (decls.isEmpty) continue;
      for (final selector in selectors) {
        final className = selector.substring(1).trim();
        if (className.isEmpty) continue;
        (out[className] ??= <String, String>{}).addAll(decls);
      }
    }
    return;
  }
  for (final child in element.children) {
    if (child is _XmlElement) {
      _collectCssRules(child, out);
    }
  }
}

Map<String, String> _parseDeclarations(String raw) {
  final result = <String, String>{};
  for (final item in raw.split(';')) {
    final colon = item.indexOf(':');
    if (colon <= 0) continue;
    final key = item.substring(0, colon).trim().toLowerCase();
    final value = item.substring(colon + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      result[key] = value;
    }
  }
  return result;
}

_SvgStyle _resolveStyle(
  _XmlElement element,
  _SvgStyle parent,
  Map<String, Map<String, String>> cssRules,
) {
  final merged = <String, String>{};

  // Presentation attributes (lowest specificity on this element).
  const presentationAttrs = [
    'fill',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-miterlimit',
    'stroke-dasharray',
    'fill-opacity',
    'stroke-opacity',
    'opacity',
    'fill-rule',
    'font-size',
    'font-weight',
  ];
  for (final attr in presentationAttrs) {
    final val = element.attributes[attr];
    if (val != null) merged[attr] = val.trim();
  }

  // CSS class rules.
  final classAttr = element.attributes['class'];
  if (classAttr != null && classAttr.isNotEmpty) {
    for (final className in classAttr.split(RegExp(r'\s+'))) {
      final rule = cssRules[className];
      if (rule != null) merged.addAll(rule);
    }
  }

  // Inline style attribute (highest specificity).
  final inlineStyle = element.attributes['style'];
  if (inlineStyle != null && inlineStyle.isNotEmpty) {
    merged.addAll(_parseDeclarations(inlineStyle));
  }

  if (merged.isEmpty) return parent;

  var fill = parent.fill;
  if (merged.containsKey('fill')) {
    fill = _parseColor(merged['fill']!);
  }
  var stroke = parent.stroke;
  if (merged.containsKey('stroke')) {
    stroke = _parseColor(merged['stroke']!);
  }
  final strokeWidth = merged.containsKey('stroke-width')
      ? (_parseLength(merged['stroke-width']) ?? parent.strokeWidth)
      : parent.strokeWidth;
  final strokeCap = switch (merged['stroke-linecap']?.toLowerCase()) {
    'round' => StrokeCap.round,
    'square' => StrokeCap.square,
    'butt' => StrokeCap.butt,
    _ => parent.strokeCap,
  };
  final strokeJoin = switch (merged['stroke-linejoin']?.toLowerCase()) {
    'round' => StrokeJoin.round,
    'bevel' => StrokeJoin.bevel,
    'miter' => StrokeJoin.miter,
    _ => parent.strokeJoin,
  };
  final strokeMiterLimit = merged.containsKey('stroke-miterlimit')
      ? (double.tryParse(merged['stroke-miterlimit']!) ??
          parent.strokeMiterLimit)
      : parent.strokeMiterLimit;
  var dashArray = parent.dashArray;
  if (merged.containsKey('stroke-dasharray')) {
    dashArray = _parseDashArray(merged['stroke-dasharray']!);
  }
  final fillOpacity = merged.containsKey('fill-opacity')
      ? (double.tryParse(merged['fill-opacity']!) ?? parent.fillOpacity)
      : parent.fillOpacity;
  final strokeOpacity = merged.containsKey('stroke-opacity')
      ? (double.tryParse(merged['stroke-opacity']!) ?? parent.strokeOpacity)
      : parent.strokeOpacity;
  final ownOpacity = merged.containsKey('opacity')
      ? (double.tryParse(merged['opacity']!) ?? 1.0)
      : 1.0;
  final fillRule = switch (merged['fill-rule']?.toLowerCase()) {
    'evenodd' => PathFillType.evenOdd,
    'nonzero' => PathFillType.nonZero,
    _ => parent.fillRule,
  };
  final fontSize = merged.containsKey('font-size')
      ? (_parseLength(merged['font-size']) ?? parent.fontSize)
      : parent.fontSize;
  final fontWeight = merged.containsKey('font-weight')
      ? _parseFontWeight(merged['font-weight']!, parent.fontWeight)
      : parent.fontWeight;

  return _SvgStyle(
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    strokeCap: strokeCap,
    strokeJoin: strokeJoin,
    strokeMiterLimit: strokeMiterLimit,
    dashArray: dashArray,
    fillOpacity: fillOpacity,
    strokeOpacity: strokeOpacity,
    opacity: parent.opacity * ownOpacity,
    fillRule: fillRule,
    fontSize: fontSize,
    fontWeight: fontWeight,
  );
}

Color? _parseColor(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty || value == 'none' || value == 'transparent') return null;
  if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length == 3) {
      final r = int.tryParse(hex[0] * 2, radix: 16);
      final g = int.tryParse(hex[1] * 2, radix: 16);
      final b = int.tryParse(hex[2] * 2, radix: 16);
      if (r != null && g != null && b != null) {
        return Color.fromARGB(255, r, g, b);
      }
    } else if (hex.length == 6) {
      final rgb = int.tryParse(hex, radix: 16);
      if (rgb != null) return Color(0xff000000 | rgb);
    } else if (hex.length == 8) {
      final rgba = int.tryParse(hex, radix: 16);
      if (rgba != null) {
        final a = rgba & 0xff;
        final rgb = (rgba >> 8) & 0xffffff;
        return Color((a << 24) | rgb);
      }
    }
    return null;
  }
  final rgbMatch = RegExp(
    r'^rgba?\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)(?:\s*,\s*([0-9.]+))?\s*\)$',
  ).firstMatch(value);
  if (rgbMatch != null) {
    final r = double.parse(rgbMatch.group(1)!).round().clamp(0, 255);
    final g = double.parse(rgbMatch.group(2)!).round().clamp(0, 255);
    final b = double.parse(rgbMatch.group(3)!).round().clamp(0, 255);
    final a = rgbMatch.group(4) == null
        ? 255
        : (double.parse(rgbMatch.group(4)!) * 255).round().clamp(0, 255);
    return Color.fromARGB(a, r, g, b);
  }
  return _namedColors[value];
}

const Map<String, Color> _namedColors = {
  'black': Color(0xff000000),
  'white': Color(0xffffffff),
  'gray': Color(0xff808080),
  'grey': Color(0xff808080),
  'silver': Color(0xffc0c0c0),
  'red': Color(0xffff0000),
  'green': Color(0xff008000),
  'blue': Color(0xff0000ff),
  'yellow': Color(0xffffff00),
  'orange': Color(0xffffa500),
  'salmon': Color(0xfffa8072),
  'navy': Color(0xff000080),
  'teal': Color(0xff008080),
  'purple': Color(0xff800080),
  'maroon': Color(0xff800000),
  'olive': Color(0xff808000),
  'lime': Color(0xff00ff00),
  'aqua': Color(0xff00ffff),
  'cyan': Color(0xff00ffff),
  'fuchsia': Color(0xffff00ff),
  'magenta': Color(0xffff00ff),
  'lightgray': Color(0xffd3d3d3),
  'lightgrey': Color(0xffd3d3d3),
  'darkgray': Color(0xffa9a9a9),
  'darkgrey': Color(0xffa9a9a9),
};

double? _parseLength(String? raw) {
  if (raw == null) return null;
  var s = raw.trim().toLowerCase();
  if (s.endsWith('px')) {
    s = s.substring(0, s.length - 2);
  } else if (s.endsWith('pt')) {
    final v = double.tryParse(s.substring(0, s.length - 2));
    return v == null ? null : v * 4 / 3;
  }
  return double.tryParse(s);
}

FontWeight _parseFontWeight(String raw, FontWeight fallback) {
  switch (raw.trim().toLowerCase()) {
    case 'normal':
    case '400':
      return FontWeight.w400;
    case 'bold':
    case '700':
      return FontWeight.w700;
    case '100':
      return FontWeight.w100;
    case '200':
      return FontWeight.w200;
    case '300':
      return FontWeight.w300;
    case '500':
      return FontWeight.w500;
    case '600':
      return FontWeight.w600;
    case '800':
      return FontWeight.w800;
    case '900':
      return FontWeight.w900;
    default:
      return fallback;
  }
}

List<double>? _parseDashArray(String raw) {
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty || trimmed == 'none') return null;
  final nums = _parseNumberList(trimmed).where((v) => v >= 0).toList();
  if (nums.isEmpty || nums.every((v) => v == 0)) return null;
  return nums.length.isOdd ? [...nums, ...nums] : nums;
}

Path _dashPath(Path source, List<double> pattern) {
  final dashed = Path();
  for (final metric in source.computeMetrics()) {
    var distance = 0.0;
    var index = 0;
    var draw = true;
    while (distance < metric.length) {
      final segment = pattern[index % pattern.length];
      final end = math.min(metric.length, distance + segment);
      if (draw && end > distance) {
        dashed.addPath(metric.extractPath(distance, end), Offset.zero);
      }
      distance = end;
      index++;
      draw = !draw;
    }
  }
  return dashed;
}

Rect? _parseViewBox(String? raw) {
  if (raw == null) return null;
  final nums = _parseNumberList(raw);
  if (nums.length != 4 || nums[2] <= 0 || nums[3] <= 0) return null;
  return Rect.fromLTWH(nums[0], nums[1], nums[2], nums[3]);
}

List<Offset> _parsePoints(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  final nums = _parseNumberList(raw);
  final points = <Offset>[];
  for (var i = 0; i + 1 < nums.length; i += 2) {
    points.add(Offset(nums[i], nums[i + 1]));
  }
  return points;
}

Matrix4? _parseTransform(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final result = Matrix4.identity();
  var found = false;
  for (final match
      in RegExp(r'([a-zA-Z]+)\s*\(([^)]*)\)').allMatches(raw)) {
    final op = match.group(1)!.toLowerCase();
    final args = _parseNumberList(match.group(2)!);
    final local = Matrix4.identity();
    switch (op) {
      case 'translate':
        if (args.isEmpty) continue;
        local.translateByDouble(args[0], args.length > 1 ? args[1] : 0.0, 0, 1);
      case 'scale':
        if (args.isEmpty) continue;
        final sx = args[0];
        final sy = args.length > 1 ? args[1] : sx;
        local.scaleByDouble(sx, sy, 1, 1);
      case 'rotate':
        if (args.isEmpty) continue;
        final radians = args[0] * math.pi / 180.0;
        if (args.length >= 3) {
          local
            ..translateByDouble(args[1], args[2], 0, 1)
            ..rotateZ(radians)
            ..translateByDouble(-args[1], -args[2], 0, 1);
        } else {
          local.rotateZ(radians);
        }
      case 'matrix':
        if (args.length < 6) continue;
        local.setValues(
          args[0], args[1], 0, 0,
          args[2], args[3], 0, 0,
          0, 0, 1, 0,
          args[4], args[5], 0, 1,
        );
      case 'skewx':
        if (args.isEmpty) continue;
        local.setEntry(0, 1, math.tan(args[0] * math.pi / 180.0));
      case 'skewy':
        if (args.isEmpty) continue;
        local.setEntry(1, 0, math.tan(args[0] * math.pi / 180.0));
      default:
        continue;
    }
    result.multiply(local);
    found = true;
  }
  return found ? result : null;
}

bool _isIdentity(Matrix4 m) {
  final s = m.storage;
  return s[0] == 1 &&
      s[1] == 0 &&
      s[2] == 0 &&
      s[3] == 0 &&
      s[4] == 0 &&
      s[5] == 1 &&
      s[6] == 0 &&
      s[7] == 0 &&
      s[8] == 0 &&
      s[9] == 0 &&
      s[10] == 1 &&
      s[11] == 0 &&
      s[12] == 0 &&
      s[13] == 0 &&
      s[14] == 0 &&
      s[15] == 1;
}

String _normalizeSvgText(String raw, bool preserve) {
  if (preserve) {
    return raw.replaceAll(RegExp(r'[\r\n\t]'), ' ');
  }
  return raw.replaceAll(RegExp(r'[\r\n\t ]+'), ' ').trim();
}

List<double> _parseNumberList(String raw) {
  final result = <double>[];
  final scanner = _PathScanner(raw);
  while (scanner.hasNumber()) {
    result.add(scanner.readNumber());
  }
  return result;
}

Path _parsePathData(String data) {
  final path = Path();
  final s = _PathScanner(data);
  var cx = 0.0;
  var cy = 0.0;
  var startX = 0.0;
  var startY = 0.0;
  var lastCtrlX = 0.0;
  var lastCtrlY = 0.0;
  var lastCmd = '';
  var cmd = '';

  while (true) {
    s.skipSeparators();
    if (s.eof) break;
    if (s.isCommand()) {
      cmd = s.readCommand();
    } else if (cmd.isEmpty) {
      break;
    }

    switch (cmd) {
      case 'M':
      case 'm':
        final rel = cmd == 'm';
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.moveTo(x, y);
        cx = startX = x;
        cy = startY = y;
        lastCmd = cmd;
        cmd = rel ? 'l' : 'L';
      case 'L':
      case 'l':
        final rel = cmd == 'l';
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.lineTo(x, y);
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'H':
      case 'h':
        final rel = cmd == 'h';
        final x = s.readNumber() + (rel ? cx : 0);
        path.lineTo(x, cy);
        cx = x;
        lastCmd = cmd;
      case 'V':
      case 'v':
        final rel = cmd == 'v';
        final y = s.readNumber() + (rel ? cy : 0);
        path.lineTo(cx, y);
        cy = y;
        lastCmd = cmd;
      case 'C':
      case 'c':
        final rel = cmd == 'c';
        final x1 = s.readNumber() + (rel ? cx : 0);
        final y1 = s.readNumber() + (rel ? cy : 0);
        final x2 = s.readNumber() + (rel ? cx : 0);
        final y2 = s.readNumber() + (rel ? cy : 0);
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'S':
      case 's':
        final rel = cmd == 's';
        final reflect =
            lastCmd == 'C' || lastCmd == 'c' || lastCmd == 'S' || lastCmd == 's';
        final x1 = reflect ? 2 * cx - lastCtrlX : cx;
        final y1 = reflect ? 2 * cy - lastCtrlY : cy;
        final x2 = s.readNumber() + (rel ? cx : 0);
        final y2 = s.readNumber() + (rel ? cy : 0);
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.cubicTo(x1, y1, x2, y2, x, y);
        lastCtrlX = x2;
        lastCtrlY = y2;
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'Q':
      case 'q':
        final rel = cmd == 'q';
        final x1 = s.readNumber() + (rel ? cx : 0);
        final y1 = s.readNumber() + (rel ? cy : 0);
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.quadraticBezierTo(x1, y1, x, y);
        lastCtrlX = x1;
        lastCtrlY = y1;
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'T':
      case 't':
        final rel = cmd == 't';
        final reflect =
            lastCmd == 'Q' || lastCmd == 'q' || lastCmd == 'T' || lastCmd == 't';
        final x1 = reflect ? 2 * cx - lastCtrlX : cx;
        final y1 = reflect ? 2 * cy - lastCtrlY : cy;
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        path.quadraticBezierTo(x1, y1, x, y);
        lastCtrlX = x1;
        lastCtrlY = y1;
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'A':
      case 'a':
        final rel = cmd == 'a';
        final rx = s.readNumber().abs();
        final ry = s.readNumber().abs();
        final rotation = s.readNumber();
        final largeArc = s.readFlag();
        final sweep = s.readFlag();
        final x = s.readNumber() + (rel ? cx : 0);
        final y = s.readNumber() + (rel ? cy : 0);
        if (rx == 0 || ry == 0) {
          path.lineTo(x, y);
        } else {
          path.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rx, ry),
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
        }
        cx = x;
        cy = y;
        lastCmd = cmd;
      case 'Z':
      case 'z':
        path.close();
        cx = startX;
        cy = startY;
        lastCmd = cmd;
        cmd = '';
      default:
        return path;
    }
  }
  return path;
}

class _PathScanner {
  _PathScanner(this.source);

  final String source;
  int _pos = 0;

  bool get eof => _pos >= source.length;

  void skipSeparators() {
    while (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d || c == 0x2c) {
        _pos++;
      } else {
        break;
      }
    }
  }

  bool isCommand() {
    if (eof) return false;
    final c = source.codeUnitAt(_pos);
    return (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
  }

  String readCommand() => source[_pos++];

  bool hasNumber() {
    skipSeparators();
    if (eof) return false;
    final c = source.codeUnitAt(_pos);
    return (c >= 0x30 && c <= 0x39) || c == 0x2b || c == 0x2d || c == 0x2e;
  }

  bool readFlag() {
    skipSeparators();
    if (eof) return false;
    final c = source.codeUnitAt(_pos++);
    return c == 0x31; // '1'
  }

  double readNumber() {
    skipSeparators();
    final start = _pos;
    if (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c == 0x2b || c == 0x2d) _pos++;
    }
    var seenDot = false;
    while (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c >= 0x30 && c <= 0x39) {
        _pos++;
      } else if (c == 0x2e && !seenDot) {
        seenDot = true;
        _pos++;
      } else {
        break;
      }
    }
    if (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c == 0x65 || c == 0x45) {
        final expStart = _pos;
        _pos++;
        if (_pos < source.length) {
          final sign = source.codeUnitAt(_pos);
          if (sign == 0x2b || sign == 0x2d) _pos++;
        }
        final digitsStart = _pos;
        while (_pos < source.length) {
          final d = source.codeUnitAt(_pos);
          if (d >= 0x30 && d <= 0x39) {
            _pos++;
          } else {
            break;
          }
        }
        if (_pos == digitsStart) _pos = expStart;
      }
    }
    if (_pos == start) return 0;
    return double.tryParse(source.substring(start, _pos)) ?? 0;
  }
}

sealed class _XmlNode {}

final class _XmlText extends _XmlNode {
  _XmlText(this.value);
  final String value;
}

final class _XmlElement extends _XmlNode {
  _XmlElement(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<_XmlNode> children = <_XmlNode>[];

  String get textContent {
    final buffer = StringBuffer();
    for (final child in children) {
      if (child is _XmlText) {
        buffer.write(child.value);
      } else if (child is _XmlElement) {
        buffer.write(child.textContent);
      }
    }
    return buffer.toString();
  }
}

class _XmlParser {
  _XmlParser(this.source);

  final String source;
  int _pos = 0;

  _XmlElement? parseRoot() {
    while (_pos < source.length) {
      _skipWhitespace();
      if (_pos >= source.length) return null;
      if (source.startsWith('<?', _pos)) {
        final end = source.indexOf('?>', _pos + 2);
        if (end < 0) return null;
        _pos = end + 2;
      } else if (source.startsWith('<!--', _pos)) {
        final end = source.indexOf('-->', _pos + 4);
        if (end < 0) return null;
        _pos = end + 3;
      } else if (source.startsWith('<!', _pos)) {
        final end = source.indexOf('>', _pos + 2);
        if (end < 0) return null;
        _pos = end + 1;
      } else if (source.codeUnitAt(_pos) == 0x3c) {
        return _parseElement();
      } else {
        _pos++;
      }
    }
    return null;
  }

  _XmlElement? _parseElement() {
    if (_pos >= source.length || source.codeUnitAt(_pos) != 0x3c) return null;
    _pos++; // '<'
    final rawName = _readName();
    if (rawName.isEmpty) return null;
    final name = _localName(rawName);
    final attrs = <String, String>{};

    while (_pos < source.length) {
      _skipWhitespace();
      if (_pos >= source.length) break;
      final c = source.codeUnitAt(_pos);
      if (c == 0x2f) {
        // '/>'
        if (_pos + 1 < source.length && source.codeUnitAt(_pos + 1) == 0x3e) {
          _pos += 2;
          return _XmlElement(name, attrs);
        }
        return null;
      }
      if (c == 0x3e) {
        // '>'
        _pos++;
        break;
      }
      final attrName = _readName();
      if (attrName.isEmpty) return null;
      _skipWhitespace();
      if (_pos < source.length && source.codeUnitAt(_pos) == 0x3d) {
        _pos++; // '='
        _skipWhitespace();
        attrs[attrName] = _readAttrValue();
      } else {
        attrs[attrName] = '';
      }
    }

    final element = _XmlElement(name, attrs);
    while (_pos < source.length) {
      final nextTag = source.indexOf('<', _pos);
      if (nextTag < 0) {
        element.children.add(_XmlText(_decodeEntities(source.substring(_pos))));
        _pos = source.length;
        break;
      }
      if (nextTag > _pos) {
        element.children
            .add(_XmlText(_decodeEntities(source.substring(_pos, nextTag))));
        _pos = nextTag;
      }
      if (source.startsWith('</', _pos)) {
        final end = source.indexOf('>', _pos + 2);
        if (end < 0) {
          _pos = source.length;
          return null;
        }
        final closeName = _localName(source.substring(_pos + 2, end).trim());
        _pos = end + 1;
        if (closeName != name) {
          throw FormatException('Mismatched XML closing tag </$closeName>');
        }
        return element;
      } else if (source.startsWith('<!--', _pos)) {
        final end = source.indexOf('-->', _pos + 4);
        if (end < 0) return null;
        _pos = end + 3;
      } else if (source.startsWith('<![CDATA[', _pos)) {
        final end = source.indexOf(']]>', _pos + 9);
        if (end < 0) return null;
        element.children.add(_XmlText(source.substring(_pos + 9, end)));
        _pos = end + 3;
      } else if (source.startsWith('<?', _pos)) {
        final end = source.indexOf('?>', _pos + 2);
        if (end < 0) return null;
        _pos = end + 2;
      } else {
        final child = _parseElement();
        if (child == null) return null;
        element.children.add(child);
      }
    }
    return null;
  }

  void _skipWhitespace() {
    while (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        _pos++;
      } else {
        break;
      }
    }
  }

  String _readName() {
    final start = _pos;
    while (_pos < source.length) {
      final c = source.codeUnitAt(_pos);
      if (c == 0x20 ||
          c == 0x09 ||
          c == 0x0a ||
          c == 0x0d ||
          c == 0x3d ||
          c == 0x2f ||
          c == 0x3e) {
        break;
      }
      _pos++;
    }
    return source.substring(start, _pos);
  }

  String _readAttrValue() {
    if (_pos >= source.length) return '';
    final quote = source.codeUnitAt(_pos);
    if (quote == 0x22 || quote == 0x27) {
      _pos++;
      final end = source.indexOf(String.fromCharCode(quote), _pos);
      if (end < 0) {
        final value = source.substring(_pos);
        _pos = source.length;
        return _decodeEntities(value);
      }
      final value = source.substring(_pos, end);
      _pos = end + 1;
      return _decodeEntities(value);
    }
    return _decodeEntities(_readName());
  }

  static String _localName(String name) {
    final colon = name.indexOf(':');
    return colon >= 0 ? name.substring(colon + 1) : name;
  }

  static String _decodeEntities(String raw) {
    if (!raw.contains('&')) return raw;
    return raw.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
        (match) {
      final token = match.group(1)!;
      if (token.startsWith('#x')) {
        final code = int.tryParse(token.substring(2), radix: 16);
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      if (token.startsWith('#')) {
        final code = int.tryParse(token.substring(1));
        return code == null ? match.group(0)! : String.fromCharCode(code);
      }
      return switch (token) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'apos' => "'",
        _ => match.group(0)!,
      };
    });
  }
}
