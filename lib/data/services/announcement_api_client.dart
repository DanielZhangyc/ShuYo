import 'dart:convert';
import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/client_user_agent.dart';
import '../models/announcement.dart';
import '../models/announcement_source.dart';
import 'http_timeout.dart';

class AnnouncementApiException implements Exception {
  const AnnouncementApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode;
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

class AnnouncementApiClient {
  AnnouncementApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? IOClient(HttpClient());

  static const maxPages = 3;
  static const maxItems = 30;
  static const maxAge = Duration(days: 180);

  final http.Client _httpClient;

  Future<List<AnnouncementListItem>> fetchAnnouncements({
    AnnouncementSource source = AnnouncementSource.official,
  }) async {
    final found = <AnnouncementListItem>[];
    final visited = <String>{};
    String? pageUrl = source.listUrl;
    for (var page = 0; page < maxPages && pageUrl != null; page++) {
      if (!visited.add(pageUrl)) break;
      http.Response response;
      try {
        response = await _getHtml(pageUrl);
      } on Object {
        if (found.isEmpty) rethrow;
        break;
      }
      final html = _decodeHtml(response);
      final pageItems =
          parseAnnouncementList(html, baseUrl: pageUrl, source: source);
      if (pageItems.isEmpty) {
        if (found.isEmpty) {
          throw const AnnouncementApiException('公告页面结构已变化，请稍后再试');
        }
        break;
      }
      found.addAll(pageItems);
      pageUrl = _nextPageUrl(html, baseUrl: pageUrl, source: source);
    }

    final today = DateTime.now();
    final cutoff =
        DateTime(today.year, today.month, today.day).subtract(maxAge);
    final unique = <String, AnnouncementListItem>{};
    for (final item in found) {
      if (item.publishedAt != null && item.publishedAt!.isBefore(cutoff)) {
        continue;
      }
      if (_isStaffOnly(item, source)) continue;
      unique.putIfAbsent(item.url, () => item);
    }
    final items = unique.values.toList();
    items.sort((a, b) {
      final left = a.publishedAt;
      final right = b.publishedAt;
      if (left == null) return right == null ? 0 : 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return items.take(maxItems).toList(growable: false);
  }

  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) async {
    final response = await _getHtml(item.url);
    return parseAnnouncementDetail(
      _decodeHtml(response),
      url: item.url,
      fallbackTitle: item.title,
      fallbackDateText: item.dateText,
      fallbackPublishedAt: item.publishedAt,
    );
  }

  static List<AnnouncementListItem> parseAnnouncementList(
    String html, {
    required String baseUrl,
    AnnouncementSource source = AnnouncementSource.official,
  }) {
    final document = html_parser.parse(html);
    final rows = switch (source.format) {
      AnnouncementListFormat.shuHome => document
              .querySelector('.ej_main .list')
              ?.querySelectorAll('ul > li > a') ??
          const <dom.Element>[],
      AnnouncementListFormat.onlyList => document
              .querySelector('div.only-list, div.only-list1')
              ?.querySelectorAll('li') ??
          const <dom.Element>[],
      AnnouncementListFormat.artList =>
        document.querySelectorAll('table.ArtList'),
      AnnouncementListFormat.vsbTable =>
        document.querySelectorAll('tr[id^="line_u"]'),
      AnnouncementListFormat.centreList => document
              .querySelector('div.list-centre-right-down')
              ?.querySelectorAll('li.clearfix') ??
          const <dom.Element>[],
      AnnouncementListFormat.rightList =>
        document.querySelector('div.right-list')?.querySelectorAll('li') ??
            const <dom.Element>[],
    };
    final items = <AnnouncementListItem>[];
    for (final row in rows) {
      final anchor = switch (source.format) {
        AnnouncementListFormat.artList => row.querySelector('a.linkfont1'),
        _ => row.localName == 'a' ? row : row.querySelector('a'),
      };
      if (anchor == null) continue;
      final titleNode = switch (source.format) {
        AnnouncementListFormat.shuHome => row.querySelector('.bt'),
        AnnouncementListFormat.artList => row.querySelector('a.linkfont1'),
        _ => anchor,
      };
      final title = _cleanText(titleNode?.text);
      final url = _resolveUrl(baseUrl, anchor.attributes['href'] ?? '');
      if (title.isEmpty || url.isEmpty) continue;
      final dateNode = switch (source.format) {
        AnnouncementListFormat.shuHome => row.querySelector('.sj'),
        AnnouncementListFormat.artList => row.querySelector('span.linkfont1'),
        AnnouncementListFormat.vsbTable => _secondTableCell(row),
        AnnouncementListFormat.centreList =>
          row.querySelector('p.list-centre-right-down-p'),
        AnnouncementListFormat.rightList => row.querySelector('span'),
        AnnouncementListFormat.onlyList => null,
      };
      final rawDate = _cleanText(dateNode?.text);
      final publishedAt = _parseDate(rawDate.isEmpty ? row.text : rawDate);
      items.add(AnnouncementListItem(
        title: title,
        url: url,
        summary: source.format == AnnouncementListFormat.shuHome
            ? _cleanText(row.querySelector('.zy')?.text)
            : '',
        dateText: publishedAt == null
            ? rawDate
            : '${publishedAt.year.toString().padLeft(4, '0')}-'
                '${publishedAt.month.toString().padLeft(2, '0')}-'
                '${publishedAt.day.toString().padLeft(2, '0')}',
        publishedAt: publishedAt,
        sourceId: source.id,
      ));
    }
    return items;
  }

  static String? _nextPageUrl(
    String html, {
    required String baseUrl,
    required AnnouncementSource source,
  }) {
    final document = html_parser.parse(html);
    final selector = switch (source.format) {
      AnnouncementListFormat.shuHome => 'span.p_pages a',
      AnnouncementListFormat.onlyList => 'div.fanye a',
      AnnouncementListFormat.artList => 'a.Next',
      AnnouncementListFormat.vsbTable => 'span.p_next a',
      AnnouncementListFormat.centreList => 'a.Next',
      AnnouncementListFormat.rightList => 'div.right-list a',
    };
    final links = document.querySelectorAll(selector);
    for (final link in links) {
      if (_cleanText(link.text) != '下页' && _cleanText(link.text) != '下一页') {
        continue;
      }
      final next = _resolveUrl(baseUrl, link.attributes['href'] ?? '');
      if (next.isNotEmpty &&
          next != baseUrl &&
          Uri.parse(next).host == Uri.parse(source.listUrl).host) {
        return next;
      }
    }
    return null;
  }

  static dom.Element? _secondTableCell(dom.Element row) {
    final cells = row.querySelectorAll('td');
    return cells.length > 1 ? cells[1] : null;
  }

  static bool _isStaffOnly(
    AnnouncementListItem item,
    AnnouncementSource source,
  ) {
    if (!source.studentOnly) return false;
    final title = item.title;
    if (source.id == 'bksy') {
      return RegExp(
        '教职工|教师|教学设计竞赛|教材跃升|本科教学学术研究|'
        '课程思政教学改革|通识示范课程立项|本科专业动态优化|'
        '人工智能赋能教育教学专项',
      ).hasMatch(title);
    }
    if (source.id == 'xgb') {
      return RegExp('辅导员|思政工作研究').hasMatch(title);
    }
    return false;
  }

  Future<http.Response> _getHtml(String url) async {
    final response = await HttpTimeout.request(
      _httpClient.get(
        Uri.parse(url),
        headers: {
          'accept': 'text/html,application/xhtml+xml',
          'user-agent': ClientUserAgent.mobileBrowser,
        },
      ),
      message: '通知公告请求超时，请稍后再试',
    );
    _ensureSuccess(response);
    return response;
  }

  static AnnouncementDetail parseAnnouncementDetail(
    String html, {
    required String url,
    String fallbackTitle = '',
    String fallbackDateText = '',
    DateTime? fallbackPublishedAt,
  }) {
    final document = html_parser.parse(html);
    final root = document.querySelector('.nry');
    final title = _cleanText(root?.querySelector('h1')?.text);
    final metadata = _parseMetadata(root?.querySelector('.xx'));
    final dateText =
        metadata.dateText.isNotEmpty ? metadata.dateText : fallbackDateText;
    final contentRoot = root?.querySelector('.v_news_content') ??
        document.querySelector('.v_news_content') ??
        document.querySelector('#vsb_content');
    final blocks = contentRoot == null
        ? <AnnouncementContentBlock>[]
        : _parseContentBlocks(contentRoot, baseUrl: url);
    final attachmentRoot = document.querySelector('td.NewsBody');
    if (attachmentRoot != null) {
      final linked = blocks
          .where((block) => block.isLink)
          .map((block) => block.value)
          .toSet();
      for (final anchor in attachmentRoot.querySelectorAll('a[href]')) {
        final href = anchor.attributes['href'] ?? '';
        if (!href.contains('DownloadAttachUrl')) continue;
        final link = _resolveUrl(url, href);
        if (link.isEmpty || !linked.add(link)) continue;
        blocks.add(AnnouncementContentBlock.link(
          link,
          label: _cleanText(anchor.text).isEmpty
              ? '查看附件'
              : _cleanText(anchor.text),
        ));
      }
    }
    return AnnouncementDetail(
      title: title.isNotEmpty ? title : fallbackTitle,
      url: url,
      dateText: dateText,
      publishedAt: _parseDate(dateText) ?? fallbackPublishedAt,
      author: metadata.author,
      department: metadata.department,
      blocks: blocks,
    );
  }

  static List<AnnouncementContentBlock> _parseContentBlocks(
    dom.Element root, {
    required String baseUrl,
  }) {
    final blocks = <AnnouncementContentBlock>[];
    final linked = <String>{};
    final imaged = <String>{};

    void addImage(dom.Element image) {
      final src = image.attributes['orisrc'] ??
          image.attributes['src'] ??
          image.attributes['vurl'] ??
          '';
      final imageUrl = _resolveUrl(baseUrl, src);
      if (imageUrl.isEmpty || !imaged.add(imageUrl)) return;
      blocks.add(AnnouncementContentBlock.image(
        imageUrl,
        alt: _cleanText(image.attributes['alt'] ?? image.attributes['title']),
      ));
    }

    void addLink(dom.Element anchor) {
      final link = _resolveUrl(baseUrl, anchor.attributes['href'] ?? '');
      if (link.isEmpty || !linked.add(link)) return;
      blocks.add(AnnouncementContentBlock.link(
        link,
        label:
            _cleanText(anchor.text).isEmpty ? '查看附件' : _cleanText(anchor.text),
      ));
    }

    // VSB renders some PDFs through JavaScript. The page embeds image URLs for
    // each PDF page, which can be displayed with the same image widget as photos.
    for (final script in root.querySelectorAll('script')) {
      final code = script.text;
      final pdf = RegExp(r'''showVsbpdfIframe\(\s*["']([^"']+\.pdf)''',
              caseSensitive: false)
          .firstMatch(code);
      if (pdf == null) continue;
      for (final match in RegExp(r'''["']([^"']+\.(?:jpg|jpeg|png))["']''',
              caseSensitive: false)
          .allMatches(code)) {
        final imageUrl = _resolveUrl(baseUrl, match.group(1) ?? '');
        if (imageUrl.isEmpty || !imaged.add(imageUrl)) continue;
        blocks.add(AnnouncementContentBlock.image(imageUrl));
      }
      final pdfUrl = _resolveUrl(baseUrl, pdf.group(1) ?? '');
      if (pdfUrl.isNotEmpty && linked.add(pdfUrl)) {
        blocks.add(AnnouncementContentBlock.link(
          pdfUrl,
          label: '查看原始 PDF',
        ));
      }
    }

    void visit(dom.Element element) {
      final tag = element.localName;
      if (tag == 'style' || tag == 'script') return;
      if (tag == 'table') {
        final rows = element
            .querySelectorAll('tr')
            .map((row) {
              return row.children
                  .where((cell) =>
                      cell.localName == 'td' || cell.localName == 'th')
                  .map((cell) => _cleanText(_visibleText(cell)))
                  .toList();
            })
            .where((row) => row.any((cell) => cell.isNotEmpty))
            .toList();
        if (rows.isNotEmpty) {
          blocks.add(AnnouncementContentBlock.table(rows));
        }
        for (final image in element.querySelectorAll('img')) {
          addImage(image);
        }
        for (final anchor in element.querySelectorAll('a[href]')) {
          addLink(anchor);
        }
        return;
      }
      if (tag == 'img') {
        addImage(element);
        return;
      }
      if (tag == 'a') {
        addLink(element);
        return;
      }
      if (tag == 'p' || tag == 'li' || tag == 'h2' || tag == 'h3') {
        final text = _cleanText(_visibleText(element));
        final anchors = element.querySelectorAll('a[href]');
        if (text.isNotEmpty &&
            !(anchors.length == 1 && _cleanText(anchors.single.text) == text)) {
          blocks.add(AnnouncementContentBlock.text(
            tag == 'li' ? '• $text' : text,
          ));
        }
        for (final image in element.querySelectorAll('img')) {
          addImage(image);
        }
        for (final anchor in anchors) {
          addLink(anchor);
        }
        return;
      }
      for (final child in element.children) {
        visit(child);
      }
    }

    for (final child in root.children) {
      visit(child);
    }
    if (blocks.isEmpty) {
      final text = _cleanText(_visibleText(root));
      if (text.isNotEmpty) blocks.add(AnnouncementContentBlock.text(text));
    }
    return blocks;
  }

  static String _visibleText(dom.Node node) {
    if (node is dom.Text) return node.text;
    if (node is! dom.Element ||
        node.localName == 'script' ||
        node.localName == 'style') {
      return '';
    }
    return node.nodes.map(_visibleText).join(' ');
  }

  static _AnnouncementMetadata _parseMetadata(dom.Element? element) {
    var dateText = '';
    var author = '';
    var department = '';
    for (final span in element?.querySelectorAll('span') ?? const []) {
      final text = _cleanText(span.text);
      if (text.startsWith('发布时间：')) {
        dateText = text.substring('发布时间：'.length).trim();
      } else if (text.startsWith('投稿：')) {
        author = text.substring('投稿：'.length).trim();
      } else if (text.startsWith('部门：')) {
        department = text.substring('部门：'.length).trim();
      }
    }
    return _AnnouncementMetadata(
      dateText: dateText,
      author: author,
      department: department,
    );
  }

  static DateTime? _parseDate(String value) {
    final match =
        RegExp(r'(\d{4})[.\-/年](\d{1,2})[.\-/月](\d{1,2})').firstMatch(value);
    if (match == null) {
      return null;
    }
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    if (year == null || month == null || day == null) {
      return null;
    }
    return DateTime(year, month, day);
  }

  static String _resolveUrl(String baseUrl, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('javascript:')) {
      return '';
    }
    try {
      final resolved = Uri.parse(baseUrl).resolve(trimmed);
      return resolved.scheme == 'https' || resolved.scheme == 'http'
          ? resolved.toString()
          : '';
    } on FormatException {
      return '';
    }
  }

  static String _cleanText(String? value) {
    return (value ?? '')
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AnnouncementApiException(
        '通知公告请求失败',
        statusCode: response.statusCode,
      );
    }
  }

  static String _decodeHtml(http.Response response) {
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

class _AnnouncementMetadata {
  const _AnnouncementMetadata({
    required this.dateText,
    required this.author,
    required this.department,
  });

  final String dateText;
  final String author;
  final String department;
}
