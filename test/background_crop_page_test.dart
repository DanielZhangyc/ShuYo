import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/profile/background_crop_page.dart';

void main() {
  testWidgets('background crop uses the supplied rectangular ratio', (
    tester,
  ) async {
    final image = await tester.runAsync(() => _testImage());
    await _open(tester, image!, aspectRatio: 390 / 122);
    await _waitUntilReady(tester);

    final crop = tester.widget<Crop>(find.byType(Crop));
    expect(crop.withCircleUi, isFalse);
    expect(crop.interactive, isTrue);
    expect(crop.fixCropRect, isTrue);
    expect(crop.aspectRatio, 390 / 122);
    expect(find.text('双指缩放并拖动图片'), findsOneWidget);
  });

  for (final aspectRatio in [320 / 122, 768 / 122]) {
    testWidgets('actual crop produces PNG with ratio $aspectRatio', (
      tester,
    ) async {
      final image = await tester.runAsync(() => _testImage());
      Uint8List? result;
      await _open(
        tester,
        image!,
        aspectRatio: aspectRatio,
        onResult: (value) => result = value,
      );
      await _waitUntilReady(tester);
      await tester.tap(find.text('确认'));
      await _waitUntil(tester, () => result != null);

      expect(result!.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final decoded = (await tester.runAsync(() => _decode(result!)))!;
      expect(decoded.width, lessThanOrEqualTo(480));
      expect(decoded.height, lessThan(320));
      // The cropper rounds both dimensions down to whole pixels.
      expect(
        (decoded.width - decoded.height * aspectRatio).abs(),
        lessThan(aspectRatio + 1),
      );
    });
  }

  testWidgets('dragging changes pixels and reset restores the original crop', (
    tester,
  ) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    Future<Uint8List> cropWith({bool drag = false, bool reset = false}) async {
      Uint8List? result;
      await _open(tester, image, onResult: (value) => result = value);
      await _waitUntilReady(tester);
      if (drag) {
        await tester.drag(find.byType(Crop), const Offset(0, 80));
        await tester.pump();
      }
      if (reset) {
        await tester.tap(find.text('重置'));
        await _waitUntilReady(tester);
      }
      await tester.tap(find.text('确认'));
      await _waitUntil(tester, () => result != null);
      await tester.pumpAndSettle();
      return result!;
    }

    final initial = await cropWith();
    final moved = await cropWith(drag: true);
    final reset = await cropWith(drag: true, reset: true);
    expect(moved, isNot(orderedEquals(initial)));
    expect(reset, orderedEquals(initial));
  });

  testWidgets('two-finger zoom changes the exported crop size', (tester) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    Uint8List? result;
    await _open(tester, image, onResult: (value) => result = value);
    await _waitUntilReady(tester);
    final center = tester.getCenter(find.byType(Crop));
    final first = await tester.startGesture(
      center - const Offset(50, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(50, 0),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(center - const Offset(100, 0));
    await second.moveTo(center + const Offset(100, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.tap(find.text('确认'));
    await _waitUntil(tester, () => result != null);
    final decoded = (await tester.runAsync(() => _decode(result!)))!;
    expect(decoded.width, lessThan(350));
  });

  testWidgets(
    'changing the viewport ratio replaces the editor and output ratio',
    (tester) async {
      final image = (await tester.runAsync(() => _testImage()))!;
      final ratio = ValueNotifier<double>(390 / 122);
      addTearDown(ratio.dispose);
      Uint8List? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<Uint8List>(
                      MaterialPageRoute(
                        builder: (_) => ValueListenableBuilder<double>(
                          valueListenable: ratio,
                          builder: (_, value, __) => BackgroundCropPage(
                            image: image,
                            aspectRatio: value,
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await _waitUntilReady(tester);
      final previous = tester.widget<Crop>(find.byType(Crop));
      ratio.value = 844 / 122;
      await tester.pump();
      previous.onCropped(CropSuccess(image));
      previous.onStatusChanged?.call(CropStatus.ready);
      await _waitUntilReady(tester);
      final current = tester.widget<Crop>(find.byType(Crop));
      expect(current.aspectRatio, 844 / 122);
      expect(current.key, isNot(previous.key));
      expect(result, isNull);
      await tester.tap(find.text('确认'));
      await _waitUntil(tester, () => result != null);
      final decoded = (await tester.runAsync(() => _decode(result!)))!;
      expect(
        (decoded.width - decoded.height * ratio.value).abs(),
        lessThan(ratio.value + 1),
      );
    },
  );

  testWidgets('large photos are bounded before entering the cropper', (
    tester,
  ) async {
    final image = await tester.runAsync(
      () => _testImage(width: 4096, height: 3072),
    );
    await _open(tester, image!);
    await _waitUntilReady(tester);
    final crop = tester.widget<Crop>(find.byType(Crop));
    final decoded = (await tester.runAsync(() => _decode(crop.image)))!;
    expect(decoded.width, 2048);
    expect(decoded.height, 1536);
    expect(crop.image.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  for (final orientation in [2, 6, 8]) {
    testWidgets('EXIF orientation $orientation is baked into preview pixels', (
      tester,
    ) async {
      await _open(tester, _orientedJpeg(orientation));
      await _waitUntilReady(tester);
      final crop = tester.widget<Crop>(find.byType(Crop));
      final decoded = (await tester.runAsync(() => _decode(crop.image)))!;
      final rotated = orientation != 2;
      expect(decoded.width, rotated ? 20 : 40);
      expect(decoded.height, rotated ? 40 : 20);
      final firstColor = _pixel(decoded, rotated ? 10 : 5, rotated ? 5 : 10);
      final lastColor = _pixel(decoded, rotated ? 10 : 35, rotated ? 35 : 10);
      if (orientation == 6) {
        expect(firstColor.$1, greaterThan(200));
        expect(lastColor.$3, greaterThan(200));
      } else {
        expect(firstColor.$3, greaterThan(200));
        expect(lastColor.$1, greaterThan(200));
      }
    });
  }

  testWidgets('invalid images show a recoverable error and can be cancelled', (
    tester,
  ) async {
    var returned = false;
    await _open(
      tester,
      Uint8List.fromList([1, 2, 3]),
      onResult: (value) {
        expect(value, isNull);
        returned = true;
      },
    );
    await _waitUntil(tester, () => find.text('重试').evaluate().isNotEmpty);
    expect(find.text('无法读取这张图片，请重试或选择其他图片'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNull);
    await tester.tap(find.text('重试'));
    await _waitUntil(tester, () => find.text('重试').evaluate().isNotEmpty);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(returned, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel ignores crop callbacks during the closing transition', (
    tester,
  ) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    var completions = 0;
    await _open(
      tester,
      image,
      onResult: (value) {
        expect(value, isNull);
        completions++;
      },
    );
    await _waitUntilReady(tester);
    final crop = tester.widget<Crop>(find.byType(Crop));
    await tester.tap(find.byType(BackButton));
    crop.onCropped(CropSuccess(image));
    crop.onStatusChanged?.call(CropStatus.ready);
    await tester.pumpAndSettle();
    crop.onCropped(CropSuccess(image));
    expect(completions, 1);
    expect(find.text('选择图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system back ignores a late result before disposal', (
    tester,
  ) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    Uint8List? result;
    await _open(tester, image, onResult: (value) => result = value);
    await _waitUntilReady(tester);
    final crop = tester.widget<Crop>(find.byType(Crop));
    await tester.binding.handlePopRoute();
    crop.onCropped(CropSuccess(image));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.text('选择图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset ignores callbacks from the previous editor', (
    tester,
  ) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    await _open(tester, image);
    await _waitUntilReady(tester);
    final previous = tester.widget<Crop>(find.byType(Crop));
    await tester.tap(find.text('重置'));
    previous.onCropped(CropSuccess(image));
    previous.onStatusChanged?.call(CropStatus.ready);
    await _waitUntilReady(tester);
    expect(find.byType(BackgroundCropPage), findsOneWidget);
    expect(tester.widget<Crop>(find.byType(Crop)).key, isNot(previous.key));
    expect(tester.takeException(), isNull);
  });

  testWidgets('crop failure stays open and allows retry', (tester) async {
    final image = (await tester.runAsync(() => _testImage()))!;
    await _open(tester, image);
    await _waitUntilReady(tester);
    final crop = tester.widget<Crop>(find.byType(Crop));
    crop.onStatusChanged?.call(CropStatus.cropping);
    crop.onCropped(CropFailure(StateError('test failure')));
    crop.onStatusChanged?.call(CropStatus.ready);
    await tester.pumpAndSettle();
    expect(find.text('背景图裁剪失败，请重试'), findsOneWidget);
    expect(_confirm(tester).onPressed, isNotNull);
    expect(find.byType(BackgroundCropPage), findsOneWidget);
  });
}

Future<void> _open(
  WidgetTester tester,
  Uint8List image, {
  double aspectRatio = 390 / 122,
  ValueChanged<Uint8List?>? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          return Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.of(context).push<Uint8List>(
                  MaterialPageRoute(
                    builder: (_) => BackgroundCropPage(
                      image: image,
                      aspectRatio: aspectRatio,
                    ),
                  ),
                );
                onResult?.call(result);
              },
              child: const Text('选择图片'),
            ),
          );
        },
      ),
    ),
  );
  await tester.tap(find.text('选择图片'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

TextButton _confirm(WidgetTester tester) =>
    tester.widget<TextButton>(find.widgetWithText(TextButton, '确认'));

Future<void> _waitUntilReady(WidgetTester tester) => _waitUntil(tester, () {
      return find.byType(Crop).evaluate().isNotEmpty &&
          _confirm(tester).onPressed != null;
    });

Future<void> _waitUntil(WidgetTester tester, bool Function() condition) async {
  await tester.pump();
  for (var attempt = 0; attempt < 500; attempt++) {
    if (condition()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('Timed out waiting for image processing');
}

Future<Uint8List> _testImage({int width = 480, int height = 320}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (var row = 0; row < 8; row++) {
    canvas.drawRect(
      Rect.fromLTWH(0, height * row / 8, width.toDouble(), height / 8),
      Paint()..color = Color.fromARGB(255, row * 30, 240 - row * 30, row * 20),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
    picture.dispose();
  }
}

typedef _DecodedImage = ({int width, int height, Uint8List pixels});

Future<_DecodedImage> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = (await frame.image.toByteData())!;
      return (
        width: frame.image.width,
        height: frame.image.height,
        pixels: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

(int, int, int) _pixel(_DecodedImage image, int x, int y) {
  final offset = (y * image.width + x) * 4;
  return (
    image.pixels[offset],
    image.pixels[offset + 1],
    image.pixels[offset + 2],
  );
}

Uint8List _orientedJpeg(int orientation) {
  // A generated 40 x 20 JPEG, red on the left and blue on the right.
  final jpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsK'
    'CwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQU'
    'FBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAUACgDASIA'
    'AhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQA'
    'AAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3'
    'ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWm'
    'p6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEA'
    'AwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSEx'
    'BhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElK'
    'U1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3'
    'uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD50ooo'
    'r8MP9Uzgfir/AMwv/tr/AOyVwFd/8Vf+YX/21/8AZK4Cv9VPBL/kgMu/7i/+n6h/mv4v/wDJb4//'
    'ALh/+maYUUUV+5H44e+0UUV/hyf7FnA/FX/mF/8AbX/2SuAoor/VTwS/5IDLv+4v/p+of5r+L/8A'
    'yW+P/wC4f/pmmFFFFfuR+OH/2Q==',
  );
  return Uint8List.fromList([
    ...jpeg.take(2),
    0xff, 0xe1, 0, 34, // APP1 segment with one EXIF orientation tag.
    0x45, 0x78, 0x69, 0x66, 0, 0,
    0x49, 0x49, 42, 0, 8, 0, 0, 0,
    1, 0, 0x12, 1, 3, 0, 1, 0, 0, 0,
    orientation, 0, 0, 0, 0, 0, 0, 0,
    ...jpeg.skip(2),
  ]);
}
