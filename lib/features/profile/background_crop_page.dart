import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

class BackgroundCropPage extends StatefulWidget {
  const BackgroundCropPage({
    super.key,
    required this.image,
    required this.aspectRatio,
  }) : assert(aspectRatio > 0 && aspectRatio < double.infinity);

  final Uint8List image;
  final double aspectRatio;

  @override
  State<BackgroundCropPage> createState() => _BackgroundCropPageState();
}

class _BackgroundCropPageState extends State<BackgroundCropPage> {
  CropController _controller = CropController();
  Uint8List? _preparedImage;
  int _editorRevision = 0;
  bool _loadFailed = false;
  bool _ready = false;
  bool _cropping = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _prepareImage();
  }

  @override
  void didUpdateWidget(covariant BackgroundCropPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.aspectRatio != widget.aspectRatio) {
      _controller = CropController();
      _editorRevision++;
      _ready = false;
      _cropping = false;
    }
  }

  Future<void> _prepareImage() async {
    try {
      // Bake the platform decoder's EXIF orientation into PNG pixels and bound
      // the image passed to the Dart cropper, including for large camera photos.
      final buffer = await ui.ImmutableBuffer.fromUint8List(widget.image);
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (width, height) {
          final scale = math.min(1.0, 2048 / math.max(width, height));
          return ui.TargetImageSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          );
        },
      );
      late final ByteData? data;
      try {
        final frame = await codec.getNextFrame();
        try {
          data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (data == null) throw StateError('Unable to prepare image');
      if (!mounted || _closed) return;
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      setState(() => _preparedImage = bytes);
    } catch (_) {
      if (!mounted || _closed) return;
      setState(() => _loadFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final revision = _editorRevision;
    final image = _preparedImage;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: Colors.white,
      disabledForegroundColor: Colors.white38,
    );
    return PopScope<Uint8List>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _closed = true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: BackButton(onPressed: () => _finish(null)),
          title: const Text('调整背景图', style: TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              style: buttonStyle,
              onPressed: _ready && !_cropping ? _crop : null,
              child: const Text('确认'),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: _loadFailed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '无法读取这张图片，请重试或选择其他图片',
                              style: TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                            TextButton(
                              style: buttonStyle,
                              onPressed: _retry,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : image == null
                        ? const Center(child: CircularProgressIndicator())
                        : Stack(
                            children: [
                              AbsorbPointer(
                                absorbing: _cropping,
                                child: Crop(
                                  key: ValueKey(revision),
                                  image: image,
                                  controller: _controller,
                                  onCropped: (result) =>
                                      _onCropped(result, revision),
                                  onStatusChanged: (status) =>
                                      _onStatusChanged(status, revision),
                                  aspectRatio: widget.aspectRatio,
                                  interactive: true,
                                  fixCropRect: true,
                                  initialRectBuilder:
                                      InitialRectBuilder.withSizeAndRatio(
                                    size: 0.9,
                                    aspectRatio: widget.aspectRatio,
                                  ),
                                  maskColor:
                                      Colors.black.withValues(alpha: 0.72),
                                  baseColor: Colors.black,
                                  progressIndicator: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                    ),
                                  ),
                                  cornerDotBuilder: (_, __) =>
                                      const SizedBox.shrink(),
                                  willUpdateScale: (scale) => scale <= 8,
                                ),
                              ),
                              if (_cropping)
                                const Center(
                                  child:
                                      CircularProgressIndicator(strokeWidth: 3),
                                ),
                            ],
                          ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '双指缩放并拖动图片',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: buttonStyle,
                      onPressed: _ready && !_cropping ? _reset : null,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重置'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onStatusChanged(CropStatus status, int revision) {
    if (!mounted || _closed || revision != _editorRevision) return;
    final ready = status == CropStatus.ready;
    if (_ready != ready) setState(() => _ready = ready);
  }

  void _crop() {
    if (!_ready || _cropping || _closed) return;
    setState(() => _cropping = true);
    _controller.crop();
  }

  void _reset() {
    if (!_ready || _cropping || _closed) return;
    setState(() {
      _controller = CropController();
      _editorRevision++;
      _ready = false;
    });
  }

  void _retry() {
    setState(() => _loadFailed = false);
    _prepareImage();
  }

  void _finish(Uint8List? image) {
    if (!mounted || _closed) return;
    _closed = true;
    Navigator.of(context).pop(image);
  }

  void _onCropped(CropResult result, int revision) {
    if (!mounted || _closed || revision != _editorRevision) return;
    switch (result) {
      case CropSuccess(:final croppedImage):
        _finish(croppedImage);
      case CropFailure():
        setState(() => _cropping = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('背景图裁剪失败，请重试')));
    }
  }
}
