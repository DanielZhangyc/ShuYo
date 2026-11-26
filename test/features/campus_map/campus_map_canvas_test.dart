import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shuyo/data/models/campus_map.dart';
import 'package:shuyo/features/campus_map/campus_map_camera.dart';
import 'package:shuyo/features/campus_map/campus_map_canvas.dart';
import 'package:shuyo/features/campus_map/campus_map_svg.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final data = CampusMapData.fromJson(
    jsonDecode(File('assets/campus_map/map_data.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  const testSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <defs><style>.b{fill:#fff;stroke:#333;stroke-width:1px}.d{fill:none;stroke:salmon;stroke-dasharray:2 2}</style></defs>
  <g id="building"><rect class="b" x="180" y="180" width="40" height="30"/></g>
  <path class="d" d="M10 10h80v20z"/>
  <text transform="translate(185 198)" xml:space="preserve">  A 楼</text>
</svg>
''';

  CampusMapCameraController createCamera({bool reducedMotion = false}) {
    final camera = CampusMapCameraController();
    camera.setViewportSize(const Size(390, 700), nowMs: 0);
    camera.configure(
      bounds: const Rect.fromLTWH(0, 0, 1000, 1000),
      initialView: const CampusMapView(
        center: CampusMapPoint(200, 200),
        zoom: 2,
      ),
      bottomInset: 0,
      active: true,
      reducedMotion: reducedMotion,
    );
    return camera;
  }

  void fling(CampusMapCameraController camera) {
    var t = 0.0;
    camera.onPointerDown(1, const Offset(190, 350), t);
    for (var i = 1; i <= 4; i++) {
      t += 16;
      camera.onPointerMove(1, Offset(190 - i * 8, 350), t);
    }
    camera.onPointerUp(
      1,
      const Offset(158, 350),
      t,
      nowMs: t,
      cancelled: false,
      hitTestPlace: (_) => null,
      onSingleTap: (_) {},
    );
  }

  group('CampusMapSvgDocument', () {
    test('parses all three bundled campus SVGs with complete feature paths', () {
      for (final campus in data.campuses) {
        final raw = File(campus.asset).readAsStringSync();
        final doc = CampusMapSvgDocument.parse(raw);
        expect(doc.viewBox.width, closeTo(campus.viewBox[2], 1e-3));
        expect(doc.viewBox.height, closeTo(campus.viewBox[3], 1e-3));
        expect(doc.drawOpCount, greaterThan(0));
        for (final place
            in data.places.where((p) => p.campusId == campus.id)) {
          for (final fid in place.featureIds) {
            final paths = doc.featurePathsById[fid];
            expect(paths, isNotNull, reason: '${campus.id}:$fid missing');
            expect(paths, isNotEmpty, reason: '${campus.id}:$fid empty');
            final box = doc.featureBoundsById[fid];
            expect(box, isNotNull);
            expect(box!.width, greaterThan(0));
            expect(box.height, greaterThan(0));
          }
        }
      }
    });

    test('strips disallowed elements and rejects non-SVG input', () {
      final doc = CampusMapSvgDocument.parse(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<script>alert(1)</script><image href="https://evil.test/x.png"/>'
        '<rect id="ok" x="10" y="10" width="20" height="20"/></svg>',
      );
      expect(doc.featurePathsById['ok'], hasLength(1));
      expect(
        () => CampusMapSvgDocument.parse('<html><body>not svg</body></html>'),
        throwsFormatException,
      );
    });
  });

  group('CampusMapCameraController', () {
    test('pan translates camera accurately and stays within bounds', () {
      final camera = createCamera();
      final before = camera.view;
      camera.onPointerDown(1, const Offset(190, 350), 0);
      camera.onPointerMove(1, const Offset(210, 360), 16);
      expect(
        camera.view.left,
        closeTo(before.left - 20 / 390 * before.width, 1e-6),
      );
      expect(
        camera.view.top,
        closeTo(before.top - 10 / 700 * before.height, 1e-6),
      );
      camera.onPointerUp(
        1,
        const Offset(210, 360),
        120,
        nowMs: 120,
        cancelled: false,
        hitTestPlace: (_) => null,
        onSingleTap: (_) {},
      );
      expect(camera.hasActiveMotion, isFalse);
    });

    test('inertia travels the same distance at 60Hz and 120Hz', () {
      final slow = createCamera();
      final fast = createCamera();
      fling(slow);
      fling(fast);
      expect(slow.hasActiveMotion, isTrue);
      expect(fast.hasActiveMotion, isTrue);

      var tSlow = 64.0;
      var tFast = 64.0;
      for (var i = 0; i < 24; i++) {
        tSlow += 1000 / 60;
        slow.tick(tSlow);
      }
      for (var i = 0; i < 48; i++) {
        tFast += 1000 / 120;
        fast.tick(tFast);
      }
      expect(slow.view.left, closeTo(fast.view.left, 1e-4));

      for (var i = 0; i < 24; i++) {
        tSlow += 1000 / 60;
        slow.tick(tSlow);
      }
      for (var i = 0; i < 48; i++) {
        tFast += 1000 / 120;
        fast.tick(tFast);
      }
      expect(slow.view.left, closeTo(fast.view.left, 1e-4));
    });

    test('holding finger before release does not launch inertia', () {
      final camera = createCamera();
      camera.onPointerDown(1, const Offset(190, 350), 0);
      camera.onPointerMove(1, const Offset(150, 350), 16);
      camera.onPointerUp(
        1,
        const Offset(150, 350),
        140,
        nowMs: 140,
        cancelled: false,
        hitTestPlace: (_) => null,
        onSingleTap: (_) {},
      );
      expect(camera.hasActiveMotion, isFalse);
    });

    test('interrupted fling tap stops inertia without selecting a building', () {
      final camera = createCamera();
      fling(camera);
      camera.tick(144);
      var tapped = false;
      camera.onPointerDown(2, const Offset(190, 350), 144);
      expect(camera.hasActiveMotion, isFalse);
      camera.onPointerUp(
        2,
        const Offset(190, 350),
        160,
        nowMs: 160,
        cancelled: false,
        hitTestPlace: (_) => 'building',
        onSingleTap: (_) => tapped = true,
      );
      expect(tapped, isFalse);
    });

    test('reduced motion disables inertia and focuses immediately', () {
      final camera = createCamera(reducedMotion: true);
      fling(camera);
      expect(camera.hasActiveMotion, isFalse);
      camera.setBottomInset(210, nowMs: 100);
      camera.focus(const Offset(200, 195), nowMs: 100);
      expect(camera.hasActiveMotion, isFalse);
      expect(camera.worldToScreen(const Offset(200, 195)).dy, closeTo(245, 1e-4));
    });

    test('pinch zoom anchors midpoint and hands off smoothly to one finger', () {
      final camera = createCamera();
      final anchor = camera.worldToScreen(const Offset(200, 200));
      camera.onPointerDown(1, Offset(anchor.dx - 40, anchor.dy), 0);
      camera.onPointerDown(2, Offset(anchor.dx + 40, anchor.dy), 0);
      camera.onPointerMove(1, Offset(anchor.dx - 80, anchor.dy), 16);
      camera.onPointerMove(2, Offset(anchor.dx + 80, anchor.dy), 16);
      final afterPinch = camera.worldToScreen(const Offset(200, 200));
      expect(afterPinch.dx, closeTo(anchor.dx, 1e-4));
      expect(afterPinch.dy, closeTo(anchor.dy, 1e-4));

      camera.onPointerUp(
        2,
        Offset(anchor.dx + 80, anchor.dy),
        32,
        nowMs: 32,
        cancelled: false,
        hitTestPlace: (_) => null,
        onSingleTap: (_) {},
      );
      final afterLift = camera.view;
      camera.onPointerMove(1, Offset(anchor.dx - 70, anchor.dy), 48);
      expect(
        camera.view.left,
        closeTo(afterLift.left - 10 / 390 * afterLift.width, 1e-4),
      );
    });

    test('focus centers above bottomInset and adapts during viewport resize', () {
      final camera = createCamera();
      camera.setBottomInset(210, nowMs: 0);
      camera.focus(
        const Offset(200, 195),
        box: const Rect.fromLTWH(180, 180, 40, 30),
        nowMs: 0,
      );
      camera.tick(80);
      camera.setViewportSize(const Size(390, 400), nowMs: 80);
      camera.setViewportSize(const Size(390, 700), nowMs: 120);
      camera.setBottomInset(280, nowMs: 120);
      camera.tick(400);
      expect(camera.hasActiveMotion, isFalse);
      final screen = camera.worldToScreen(const Offset(200, 195));
      expect(screen.dx, closeTo(195, 1e-3));
      expect(screen.dy, closeTo(210, 1e-3));
    });

    test('setting inactive stops motion and discards further pointer input', () {
      final camera = createCamera();
      fling(camera);
      camera.tick(120);
      final pausedView = camera.view;
      camera.setActive(false);
      expect(camera.hasActiveMotion, isFalse);
      camera.onPointerDown(1, const Offset(100, 350), 150);
      camera.onPointerMove(1, const Offset(200, 350), 166);
      camera.onPointerUp(
        1,
        const Offset(200, 350),
        180,
        nowMs: 180,
        cancelled: false,
        hitTestPlace: (_) => null,
        onSingleTap: (_) {},
      );
      expect(camera.view, pausedView);
    });
  });

  group('CampusMapCanvas widget', () {
    CampusMapCanvasConfiguration config({
      String svg = testSvg,
      String? selectedId,
      bool active = true,
      int focusRevision = 0,
      ValueChanged<CampusMapView>? onViewChanged,
    }) {
      final campus = CampusMapCampus.fromJson({
        'id': 'test',
        'name': '测试校区',
        'asset': 'assets/campus_map/maps/baoshan.svg',
        'viewBox': [0.0, 0.0, 1000.0, 1000.0],
        'geoTransform': {
          'a': 1.0,
          'b': 0.0,
          'c': 0.0,
          'd': 0.0,
          'e': 1.0,
          'f': 0.0,
        },
        'metersPerMapUnit': {'x': 1.0, 'y': 1.0},
        'initialView': {
          'zoom': 2.0,
          'center': {'x': 200.0, 'y': 200.0},
        },
        'backgroundColor': '#EAEADF',
      });
      final places = [
        CampusMapPlace.fromJson({
          'id': 'place_building',
          'campusId': 'test',
          'name': 'A 楼',
          'kind': '建筑',
          'address': '',
          'description': '',
          'aliases': const <String>[],
          'featureIds': const ['building'],
          'facts': const <Map<String, dynamic>>[],
          'point': {'x': 200.0, 'y': 195.0},
        }),
      ];
      return CampusMapCanvasConfiguration(
        campus: campus,
        svg: svg,
        places: places,
        accent: const Color(0xff3478d4),
        selectedPlaceId: selectedId,
        active: active,
        focusRevision: focusRevision,
        onViewChanged: onViewChanged,
      );
    }

    testWidgets('tapping building selects it and tapping background notifies',
        (tester) async {
      final tappedPlaces = <String>[];
      var backgroundTaps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 390,
            height: 700,
            child: CampusMapCanvas(
              configuration: config(),
              onPlaceTap: tappedPlaces.add,
              onMapTap: () => backgroundTaps++,
            ),
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));

      // Center of viewport maps to world (200, 200), inside building [180..220, 180..210].
      await tester.tapAt(tester.getCenter(find.byType(CampusMapCanvas)));
      await tester.pump();
      expect(tappedPlaces, ['place_building']);

      // Top-left corner maps well outside the building rect.
      await tester.tapAt(
        tester.getTopLeft(find.byType(CampusMapCanvas)) + const Offset(20, 20),
      );
      await tester.pump();
      expect(backgroundTaps, 1);
    });

    testWidgets('covered canvas ignores pointer taps and debug reports',
        (tester) async {
      final tappedPlaces = <String>[];
      var backgroundTaps = 0;
      final views = <CampusMapView>[];
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 390,
          height: 700,
          child: CampusMapCanvas(
            configuration: config(active: false, onViewChanged: views.add),
            onPlaceTap: tappedPlaces.add,
            onMapTap: () => backgroundTaps++,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tapAt(const Offset(195, 350));
      await tester.pump();
      expect(tappedPlaces, isEmpty);
      expect(backgroundTaps, 0);
      expect(views, isEmpty);
    });

    testWidgets('invalid SVG displays recoverable error state', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CampusMapCanvas(
          configuration: config(svg: '<not-svg/>'),
          onPlaceTap: (_) {},
          onMapTap: () {},
        ),
      ));
      await tester.pump();
      expect(find.text('地图画布加载失败'), findsOneWidget);
      expect(find.text('重新加载'), findsOneWidget);
    });

    testWidgets('mouse wheel zooms without throwing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SizedBox(
          width: 390,
          height: 700,
          child: CampusMapCanvas(
            configuration: config(),
            onPlaceTap: (_) {},
            onMapTap: () {},
          ),
        ),
      ));
      await tester.pump();
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(195, 350));
      tester.binding.handlePointerEvent(
        const PointerScrollEvent(
          position: Offset(195, 350),
          scrollDelta: Offset(0, -120),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });
}
