import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/announcement.dart';
import '../../data/models/announcement_source.dart';
import '../../data/repositories/announcement_repository.dart';
import '../../data/services/announcement_api_client.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/theme/custom_background.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/fullscreen_image_page.dart';

/// Horizontal padding of the detail body, also used to derive the image decode
/// width.
const double _announcementDetailPadding = 20;

/// Height reserved until an image is decoded, so the body does not jump from
/// zero height when the image arrives.
const double _announcementImagePlaceholderHeight = 180;

/// Frame budget for waiting on the push animation, roughly 1.5 seconds, kept
/// only as a safety net.
const int _maximumAnimationFrames = 90;

@visibleForTesting
const announcementImagePlaceholderKey =
    ValueKey<String>('announcement-image-placeholder');

class AnnouncementsPage extends StatefulWidget {
  const AnnouncementsPage({
    super.key,
    required this.repository,
    this.isDemo = false,
  });

  final AnnouncementRepository repository;
  final bool isDemo;

  @override
  State<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends State<AnnouncementsPage> {
  Future<_LoadedAnnouncementList>? _future;
  AnnouncementSource? _source;
  AnnouncementSource? _defaultSource;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    AnnouncementSource source;
    try {
      source = await widget.repository.defaultSource();
    } on Object {
      source = AnnouncementSource.official;
    }
    if (!mounted) return;
    setState(() {
      _source = source;
      _defaultSource = source;
      _future = _loadList(source);
    });
  }

  Future<_LoadedAnnouncementList> _loadList(
    AnnouncementSource source, {
    bool forceRefresh = false,
  }) async {
    final media = MediaQuery.maybeOf(context);
    final firstScreenHeight = media == null
        ? 740.0
        : media.size.height -
            media.padding.top -
            media.padding.bottom -
            kToolbarHeight -
            8;
    final items = await widget.repository.fetchAnnouncements(
      source: source,
      forceRefresh: forceRefresh,
    );
    final firstScreenCount =
        (firstScreenHeight / 148).ceil().clamp(0, items.length);
    final firstItems = items.take(firstScreenCount).toList();
    final previews = await Future.wait(
      firstItems.map(widget.repository.loadPreview),
    );
    return _LoadedAnnouncementList(items, {
      for (var index = 0; index < firstItems.length; index++)
        firstItems[index].url: previews[index],
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_source == null || _source == AnnouncementSource.official
            ? '通知公告'
            : _source!.name),
        actions: [
          if (!widget.isDemo)
            IconButton(
              tooltip: '选择公告来源',
              onPressed: _source == null ? null : _chooseSource,
              icon: const Icon(Icons.format_list_bulleted),
            ),
        ],
      ),
      body: _future == null ? const _AnnouncementLoadingState() : _buildList(),
    );
  }

  Widget _buildList() {
    return FutureBuilder<_LoadedAnnouncementList>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _AnnouncementLoadingState();
        }
        if (snapshot.hasError) {
          return _AnnouncementErrorState(
            message: _friendlyError(snapshot.error!),
            onRetry: _refresh,
          );
        }
        final loaded = snapshot.data!;
        final items = loaded.items;
        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 96),
                EmptyState(
                  icon: Icons.campaign_outlined,
                  title: '暂无公告',
                  message: '该来源近半年没有可展示的通知公告。',
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemBuilder: (context, index) {
              return _AnnouncementTile(
                key: ValueKey(items[index].url),
                index: index,
                item: items[index],
                repository: widget.repository,
                initialPreviewReady:
                    loaded.initialPreviews.containsKey(items[index].url),
                initialPreview: loaded.initialPreviews[items[index].url],
                onTap: () => _openDetail(items[index]),
              );
            },
            separatorBuilder: (context, index) {
              if (CustomBackgroundScope.maybeOf(context) != null) {
                return const SizedBox.shrink();
              }
              return Divider(height: 1, color: context.shuyoColors.border);
            },
            itemCount: items.length,
          ),
        );
      },
    );
  }

  Future<void> _chooseSource() async {
    var savingDefault = false;
    final choice = await showGeneralDialog<AnnouncementSource>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭公告来源菜单',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.18, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          StatefulBuilder(
              builder: (menuContext, menuSetState) => SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.only(
                            top: kToolbarHeight + 8, right: 12),
                        child: Material(
                          elevation: 12,
                          borderRadius: BorderRadius.circular(16),
                          clipBehavior: Clip.antiAlias,
                          color: Theme.of(menuContext).colorScheme.surface,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: 320,
                              maxHeight:
                                  MediaQuery.sizeOf(menuContext).height * 0.72,
                            ),
                            child: ListView(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              children: [
                                const ListTile(title: Text('公告来源')),
                                for (final source in AnnouncementSource.all)
                                  ListTile(
                                    title: Text(source.name),
                                    selected: _source == source,
                                    onTap: () =>
                                        Navigator.of(menuContext).pop(source),
                                    trailing: IconButton(
                                      tooltip: '将${source.name}设为默认',
                                      icon: Icon(_defaultSource == source
                                          ? Icons.star
                                          : Icons.star_border),
                                      onPressed: savingDefault
                                          ? null
                                          : () async {
                                              menuSetState(
                                                  () => savingDefault = true);
                                              try {
                                                await widget.repository
                                                    .setDefaultSource(source);
                                                if (mounted) {
                                                  setState(() =>
                                                      _defaultSource = source);
                                                }
                                              } on Object {
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content:
                                                          Text('默认来源保存失败，请重试'),
                                                    ),
                                                  );
                                                }
                                              } finally {
                                                if (menuContext.mounted) {
                                                  menuSetState(() =>
                                                      savingDefault = false);
                                                }
                                              }
                                            },
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )),
    );
    if (!mounted || choice == null) return;
    setState(() {
      _source = choice;
      _future = _loadList(choice);
    });
  }

  Future<void> _refresh() async {
    final source = _source;
    if (source == null) return;
    final future = _loadList(source, forceRefresh: true);
    setState(() {
      _future = future;
    });
    await future;
  }

  void _openDetail(AnnouncementListItem item) {
    Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (context) => AnnouncementDetailPage(
          repository: widget.repository,
          item: item,
        ),
      ),
    );
  }

  String _friendlyError(Object error) {
    if (error is AnnouncementApiException) {
      return error.message;
    }
    return '通知公告加载失败，请稍后重试';
  }
}

class _LoadedAnnouncementList {
  const _LoadedAnnouncementList(this.items, this.initialPreviews);

  final List<AnnouncementListItem> items;
  final Map<String, String?> initialPreviews;
}

class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({
    super.key,
    required this.repository,
    required this.item,
  });

  final AnnouncementRepository repository;
  final AnnouncementListItem item;

  @override
  State<AnnouncementDetailPage> createState() => _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  /// Route hosting this page, used to wait for the push animation to settle.
  ModalRoute<dynamic>? _route;

  Future<AnnouncementDetail>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of<dynamic>(context);
    // The request is fired on the first frame, but _load holds its result back
    // until the push animation has settled.
    _future ??= _load();
  }

  Future<AnnouncementDetail> _load() {
    // Future.wait subscribes to the request right away, which avoids an
    // unhandled async error while the animation is still running. Its
    // eagerError defaults to false, so a failure also waits for the animation.
    return Future.wait<AnnouncementDetail?>([
      widget.repository.fetchDetail(widget.item),
      _waitForRoutePushAnimation().then((_) => null),
    ]).then((results) => results.first!);
  }

  /// DOM parsing, first layout and image decoding of the body keep the raster
  /// thread busy; overlapping them with the 240ms push animation drops frames.
  /// This defers the body until the animation has settled so the two do not
  /// compete for the same frames.
  Future<void> _waitForRoutePushAnimation() {
    final route = _route;
    if (route == null) {
      return Future<void>.value();
    }
    final completer = Completer<void>();
    var frames = 0;
    void poll(Duration _) {
      final animation = route.animation;
      // On the first frame of a push, HeroController marks the incoming route
      // offstage and swaps its animation for kAlwaysCompleteAnimation (value
      // 1.0), so offstage must not be read as "already settled". A zero-duration
      // transition emits no status change either, hence polling every frame
      // instead of listening to the animation status.
      final settled = !route.offstage &&
          (animation == null ||
              animation.isCompleted ||
              !animation.isAnimating);
      // Safety net: release the body even if the animation misbehaves rather
      // than leaving it stuck in the loading state.
      if (settled || frames > _maximumAnimationFrames) {
        if (!completer.isCompleted) {
          completer.complete();
        }
        return;
      }
      frames++;
      WidgetsBinding.instance.addPostFrameCallback(poll);
    }

    WidgetsBinding.instance.addPostFrameCallback(poll);
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('公告详情'),
        actions: [
          IconButton(
            tooltip: '复制公告链接',
            icon: const Icon(Icons.share_outlined),
            onPressed: _copyLink,
          ),
          IconButton(
            tooltip: '查看原文',
            icon: const Icon(Icons.open_in_new),
            onPressed: _confirmOpenOriginal,
          ),
        ],
      ),
      body: FutureBuilder<AnnouncementDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _AnnouncementLoadingState();
          }
          if (snapshot.hasError) {
            return _AnnouncementErrorState(
              message: '公告详情加载失败，请稍后重试',
              onRetry: () async {
                setState(() {
                  _future = _load();
                });
              },
            );
          }
          final detail = snapshot.data!;
          final colors = context.shuyoColors;
          final imageUrls = detail.blocks
              .where((block) => block.isImage)
              .map((block) => block.value)
              .toList(growable: false);
          // Precompute every image's index into imageUrls to avoid an O(n²)
          // scan while building the list.
          final imageIndexByBlock = <int, int>{};
          for (var index = 0; index < detail.blocks.length; index++) {
            if (detail.blocks[index].isImage) {
              imageIndexByBlock[index] = imageIndexByBlock.length;
            }
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              _announcementDetailPadding,
              10,
              _announcementDetailPadding,
              28,
            ),
            children: [
              Text(
                detail.title,
                style: ShuYoTextStyles.title(
                  color: colors.textPrimary,
                  size: 20,
                  height: 1.22,
                  weight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _AnnouncementMetadata(detail: detail),
              const SizedBox(height: 22),
              if (!detail.hasContent)
                Text(
                  '这条公告暂时没有解析到正文。',
                  style: TextStyle(color: colors.textTertiary),
                )
              else
                ...List.generate(detail.blocks.length, (index) {
                  return _blockWidget(
                    detail.blocks[index],
                    imageUrls: imageUrls,
                    imageIndex: imageIndexByBlock[index] ?? 0,
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _blockWidget(
    AnnouncementContentBlock block, {
    required List<String> imageUrls,
    required int imageIndex,
  }) {
    if (block.isLink) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => _openExternal(block.value),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(block.label.isEmpty ? '查看链接' : block.label),
        ),
      );
    }
    if (block.isTable) {
      final colors = context.shuyoColors;
      final columnCount = block.rows.fold<int>(
        0,
        (count, row) => row.length > count ? row.length : count,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: colors.border),
            children: [
              for (final row in block.rows)
                TableRow(
                  children: [
                    for (var index = 0; index < columnCount; index++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          index < row.length ? row[index] : '',
                          style: TextStyle(color: colors.textPrimary),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      );
    }
    if (block.isImage) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: GestureDetector(
          onTap: () {
            Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => FullscreenImagePage(
                  urls: imageUrls,
                  initialIndex: imageIndex,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              block.value,
              fit: BoxFit.cover,
              // Decode at the width the body actually displays: source images
              // are often wider than 1000px, and decoding them at full size
              // makes the raster thread drop frames during the transition and
              // the scrolling that follows.
              cacheWidth: _decodeWidth(context),
              frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                if (wasSynchronouslyLoaded || frame != null) {
                  return child;
                }
                return const _AnnouncementImagePlaceholder();
              },
              errorBuilder: (context, error, stackTrace) {
                final colors = context.shuyoColors;
                return Container(
                  height: 120,
                  alignment: Alignment.center,
                  color: colors.surfaceAlt,
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                );
              },
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: SelectableText(
        block.value,
        style: TextStyle(
          fontSize: 16,
          height: 1.7,
          color: context.shuyoColors.textPrimary,
        ),
      ),
    );
  }

  /// Pixel width the body actually occupies, used as the image decode width.
  int _decodeWidth(BuildContext context) {
    final logicalWidth =
        MediaQuery.sizeOf(context).width - _announcementDetailPadding * 2;
    final pixels =
        (logicalWidth * MediaQuery.devicePixelRatioOf(context)).round();
    return pixels < 1 ? 1 : pixels;
  }

  Future<void> _openExternal(String url) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Object {
      // Keep the readable page available when the system cannot open the link.
    }
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开原网站链接')),
      );
    }
  }

  Future<void> _confirmOpenOriginal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('在浏览器中打开？'),
        content: const Text('将跳转到浏览器查看这条公告的原网页。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('打开浏览器'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _openExternal(widget.item.url);
    }
  }

  Future<void> _copyLink() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.item.url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('公告链接已复制')),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复制失败，请重试')),
      );
    }
  }
}

/// Holds the image's place until it is decoded, so the body does not jump from
/// zero height when the image arrives.
class _AnnouncementImagePlaceholder extends StatelessWidget {
  const _AnnouncementImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Container(
      key: announcementImagePlaceholderKey,
      height: _announcementImagePlaceholderHeight,
      alignment: Alignment.center,
      color: colors.surfaceAlt,
      child: Icon(Icons.image_outlined, size: 22, color: colors.textMuted),
    );
  }
}

/// The loading state carries its own repaint boundary, so during a transition
/// only this small area is re-recorded and the page layer can be reused.
class _AnnouncementLoadingState extends StatelessWidget {
  const _AnnouncementLoadingState();

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: Center(child: CircularProgressIndicator(strokeWidth: 3)),
    );
  }
}

class _AnnouncementTile extends StatefulWidget {
  const _AnnouncementTile({
    super.key,
    required this.index,
    required this.item,
    required this.repository,
    required this.initialPreviewReady,
    required this.initialPreview,
    required this.onTap,
  });

  final int index;
  final AnnouncementListItem item;
  final AnnouncementRepository repository;
  final bool initialPreviewReady;
  final String? initialPreview;
  final VoidCallback onTap;

  @override
  State<_AnnouncementTile> createState() => _AnnouncementTileState();
}

class _AnnouncementTileState extends State<_AnnouncementTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  Timer? _entranceTimer;
  int _previewGeneration = 0;
  late bool _previewReady;
  String? _resolvedPreview;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _loadPreview();
  }

  @override
  void didUpdateWidget(covariant _AnnouncementTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.url != widget.item.url ||
        oldWidget.item.sourceId != widget.item.sourceId ||
        oldWidget.item.summary != widget.item.summary ||
        oldWidget.initialPreviewReady != widget.initialPreviewReady ||
        oldWidget.initialPreview != widget.initialPreview ||
        oldWidget.repository != widget.repository) {
      _loadPreview();
    }
  }

  void _loadPreview() {
    final generation = ++_previewGeneration;
    _entranceTimer?.cancel();
    _entrance.reset();
    _previewReady =
        widget.initialPreviewReady || widget.item.summary.isNotEmpty;
    _resolvedPreview = widget.item.summary.isNotEmpty
        ? widget.item.summary
        : widget.initialPreview;
    if (_previewReady) {
      _startEntrance();
      return;
    }
    widget.repository.loadPreview(widget.item).then(
      (preview) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() {
          _previewReady = true;
          _resolvedPreview = preview;
        });
        _startEntrance();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || generation != _previewGeneration) return;
        setState(() => _previewReady = true);
        _startEntrance();
      },
    );
  }

  void _startEntrance() {
    _entranceTimer = Timer(
      Duration(milliseconds: (widget.index % 6) * 55),
      () {
        if (mounted) _entrance.forward();
      },
    );
  }

  @override
  void dispose() {
    _entranceTimer?.cancel();
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_previewReady) {
      return const SizedBox(
        height: 148,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.12, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entrance,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(
        opacity: _entrance,
        child: _tile(_resolvedPreview),
      ),
    );
  }

  Widget _tile(String? preview) {
    final item = widget.item;
    final colors = context.shuyoColors;
    return InkWell(
      onTap: widget.onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 148),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ShuYoTextStyles.title(
                        color: colors.textPrimary,
                        size: 16,
                        height: 1.26,
                        weight: FontWeight.w500,
                      ),
                    ),
                    if (preview != null && preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textTertiary,
                            fontSize: 14.5,
                            height: 1.46,
                          ),
                        ),
                      ),
                    if (item.dateText.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          item.dateText,
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.chevron_right, color: colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementMetadata extends StatelessWidget {
  const _AnnouncementMetadata({required this.detail});

  final AnnouncementDetail detail;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (detail.dateText.isNotEmpty) detail.dateText,
      if (detail.department.isNotEmpty) detail.department,
      if (detail.author.isNotEmpty) detail.author,
    ];
    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Text(
      parts.join(' · '),
      style: TextStyle(color: context.shuyoColors.textTertiary, fontSize: 13),
    );
  }
}

class _AnnouncementErrorState extends StatelessWidget {
  const _AnnouncementErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: '加载失败',
      message: message,
      action: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('重试'),
      ),
    );
  }
}
