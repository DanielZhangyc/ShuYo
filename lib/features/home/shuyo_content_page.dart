import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/shuyo_content_repository.dart';

class ShuyoContentPage extends StatefulWidget {
  const ShuyoContentPage({
    super.key,
    required this.repository,
    this.initialKind = ShuyoContentKind.announcements,
  });

  final ShuyoContentRepository repository;
  final ShuyoContentKind initialKind;

  @override
  State<ShuyoContentPage> createState() => _ShuyoContentPageState();
}

class _ShuyoContentPageState extends State<ShuyoContentPage> {
  late ShuyoContentKind _kind = widget.initialKind;
  late Future<ShuyoContentLoad> _future = widget.repository.load(_kind);

  void _select(ShuyoContentKind kind) {
    if (_kind == kind) return;
    setState(() {
      _kind = kind;
      _future = widget.repository.load(kind);
    });
  }

  Future<void> _refresh() async {
    final future = widget.repository.load(_kind);
    setState(() => _future = future);
    try {
      await future;
    } on Object {
      // The list shows the retry state through FutureBuilder.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShuYo 内容')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<ShuyoContentKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: ShuyoContentKind.announcements,
                    label: Text('ShuYo 公告'),
                  ),
                  ButtonSegment(
                    value: ShuyoContentKind.tips,
                    label: Text('使用提示'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selected) => _select(selected.first),
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<ShuyoContentLoad>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(snapshot.error.toString()),
                        const SizedBox(height: 12),
                        TextButton(
                            onPressed: _refresh, child: const Text('重试')),
                      ],
                    ),
                  );
                }
                final loaded = snapshot.data!;
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (loaded.fromCache)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            loaded.message ?? '',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      if (loaded.items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 96),
                          child: Center(child: Text('暂无${_kind.label}')),
                        ),
                      for (final item in loaded.items)
                        Card(
                          child: ListTile(
                            title: Text(item.title),
                            subtitle: Text(_date(item.createdAt)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ShuyoContentDetailPage(
                                  item: item,
                                  kind: _kind,
                                  baseUri: widget.repository.baseUri,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ShuyoContentDetailPage extends StatelessWidget {
  const ShuyoContentDetailPage({
    super.key,
    required this.item,
    required this.kind,
    required this.baseUri,
  });

  final ShuyoContentItem item;
  final ShuyoContentKind kind;
  final Uri baseUri;

  Uri? _safeImage(Uri source) {
    final uri = baseUri.resolveUri(source);
    if (uri.scheme != 'https' ||
        uri.host != baseUri.host ||
        !RegExp(r'^/api/v1/tips/images/[0-9a-f-]{36}\.(png|jpg|webp)$')
            .hasMatch(uri.path)) {
      return null;
    }
    return uri;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(kind.label)),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
          children: [
            Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              _date(item.createdAt),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            if (kind == ShuyoContentKind.announcements)
              Text(item.content,
                  style: const TextStyle(fontSize: 16, height: 1.65))
            else
              MarkdownBody(
                data: item.content,
                selectable: true,
                imageBuilder: (uri, title, alt) {
                  final safe = _safeImage(uri);
                  if (safe == null) return const Text('图片地址不可用');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Image.network(
                      safe.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) =>
                          const Text('图片暂不可用'),
                    ),
                  );
                },
                onTapLink: (text, href, title) {
                  final uri = Uri.tryParse(href ?? '');
                  if (uri?.scheme == 'https') {
                    unawaited(
                        launchUrl(uri!, mode: LaunchMode.externalApplication));
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime? date) {
  if (date == null) return '';
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
