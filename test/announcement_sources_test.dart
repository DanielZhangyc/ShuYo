import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/announcement.dart';
import 'package:shuyo/data/models/announcement_source.dart';
import 'package:shuyo/data/repositories/announcement_repository.dart';
import 'package:shuyo/data/services/announcement_api_client.dart';

void main() {
  test('all seven source profiles extract dated article links', () {
    final samples = <String, String>{
      'shu': '<div class="ej_main"><div class="list"><ul><li><a '
          'href="/info/1.htm"><p class="bt">官网通知</p><p class="sj">'
          '2026.10.06</p><p class="zy">摘要</p></a></li></ul></div></div>',
      'bksy': '<div class="only-list"><ul><li><a href="../info/2.htm">'
          '本科生通知</a> 2026年10月6日</li></ul></div>',
      'xgb': '<table class="ArtList"><tr><td><a class="linkfont1" '
          'href="/info/3.htm">本科生处通知</a></td><td><span '
          'class="linkfont1">2026-10-06</span></td></tr></table>',
      'dwygb': '<table class="ArtList"><tr><td><a class="linkfont1" '
          'href="/info/4.htm">研工部通知</a></td><td><span '
          'class="linkfont1">2026-10-06</span></td></tr></table>',
      'gs': '<table><tr id="line_u1_0"><td><a href="/info/5.htm">'
          '研究生培养通知</a></td><td>2026/10/06 09:00:00</td></tr></table>',
      'cwc': '<div class="list-centre-right-down"><ul><li class="clearfix">'
          '<a href="/info/6.htm">财务通知</a><p '
          'class="list-centre-right-down-p">2026-10-06</p>'
          '</li></ul></div>',
      'lib': '<div class="right-list"><ul><li><a href="/info/7.htm">'
          '图书馆通知</a><span>2026-10-06</span></li></ul></div>',
    };

    for (final source in AnnouncementSource.all) {
      final items = AnnouncementApiClient.parseAnnouncementList(
        samples[source.id]!,
        baseUrl: source.listUrl,
        source: source,
      );
      expect(items, hasLength(1), reason: source.id);
      expect(items.single.url,
          startsWith('https://${Uri.parse(source.listUrl).host}/'));
      expect(items.single.publishedAt, DateTime(2026, 10, 6));
      expect(items.single.sourceId, source.id);
    }
  });

  test('detail parser keeps text, tables and links in the article body', () {
    const html = '<div class="v_news_content">'
        '<p>评审结果如下：</p>'
        '<table><tr><th>姓名</th><th>学院</th></tr>'
        '<tr><td>张同学</td><td>理学院</td></tr></table>'
        '<p><a href="/files/result.pdf">下载名单</a></p>'
        '</div>';
    final detail = AnnouncementApiClient.parseAnnouncementDetail(
      html,
      url: 'https://xgb.shu.edu.cn/info/1.htm',
      fallbackTitle: '评审公示',
    );
    expect(detail.title, '评审公示');
    expect(
        detail.blocks.where((block) => block.isText).single.value, '评审结果如下：');
    expect(detail.blocks.where((block) => block.isTable).single.rows, [
      ['姓名', '学院'],
      ['张同学', '理学院'],
    ]);
    expect(detail.blocks.where((block) => block.isLink).single.value,
        'https://xgb.shu.edu.cn/files/result.pdf');
  });

  test('detail parser displays PDF pages and retains the original attachment',
      () {
    const html = '<table><tr><td class="NewsBody">'
        '<div id="vsb_content"><p><script>'
        'var vsb_pdf_image_data = ["/__local/page1.jpg", "/__local/page2.jpg"];'
        'showVsbpdfIframe("/__local/notice.pdf","100%","600");'
        '</script></p></div>'
        '<ul><li>附件<a href="/system/_content/download.jsp?'
        'urltype=news.DownloadAttachUrl&amp;wbfileid=1">附件.zip</a></li></ul>'
        '</td></tr></table>';
    final detail = AnnouncementApiClient.parseAnnouncementDetail(
      html,
      url: 'https://gs.shu.edu.cn/info/1.htm',
      fallbackTitle: '研究生通知',
    );
    expect(detail.blocks.where((block) => block.isImage).length, 2);
    expect(detail.blocks.where((block) => block.isText), isEmpty);
    expect(
        detail.blocks
            .where((block) => block.isLink)
            .map((block) => block.label),
        containsAll(['查看原始 PDF', '附件.zip']));
    final pdf = detail.blocks.firstWhere(
      (block) => block.isLink && block.label == '查看原始 PDF',
    );
    expect(pdf.value, 'https://gs.shu.edu.cn/__local/notice.pdf');
  });

  test('fetch follows next link, sorts dates and removes staff-only rows',
      () async {
    final today = DateTime.now();
    final date = '${today.year}-${today.month.toString().padLeft(2, '0')}-'
        '${today.day.toString().padLeft(2, '0')}';
    final first = '<div class="only-list"><ul>'
        '<li><a href="/old.htm">旧通知</a> 2020年01月01日</li>'
        '<li><a href="/staff.htm">关于教师教学设计竞赛的通知</a> $date</li>'
        '</ul></div><div class="fanye"><a href="tzgg/2.htm">下页</a></div>';
    final second = '<div class="only-list"><ul>'
        '<li><a href="/student.htm">本科生选课通知</a> $date</li>'
        '</ul></div>';
    final requested = <Uri>[];
    final client = AnnouncementApiClient(
      httpClient: MockClient((request) async {
        requested.add(request.url);
        if (request.url.toString() == AnnouncementSource.byId('bksy').listUrl) {
          return http.Response.bytes(utf8.encode(first), 200);
        }
        if (request.url.toString() ==
            'https://bksy.shu.edu.cn/index/tzgg/2.htm') {
          return http.Response.bytes(utf8.encode(second), 200);
        }
        return http.Response('missing', 404);
      }),
    );

    final items = await client.fetchAnnouncements(
      source: AnnouncementSource.byId('bksy'),
    );
    expect(requested, hasLength(2));
    expect(items.map((item) => item.title), ['本科生选课通知']);
  });

  test('fetch stops after three pages and returns at most thirty items',
      () async {
    final today = DateTime.now();
    final date = '${today.year}.${today.month}.${today.day}';
    var requests = 0;
    final client = AnnouncementApiClient(
      httpClient: MockClient((request) async {
        requests++;
        final rows = List.generate(
          15,
          (index) => '<li><a href="/info/$requests-$index.htm">'
              '<p class="bt">公告 $requests-$index</p>'
              '<p class="sj">$date</p></a></li>',
        ).join();
        final html = '<div class="ej_main"><div class="list"><ul>'
            '$rows</ul></div></div><span class="p_pages">'
            '<a href="next$requests.htm">下页</a></span>';
        return http.Response.bytes(utf8.encode(html), 200);
      }),
    );

    final items = await client.fetchAnnouncements();
    expect(requests, 3);
    expect(items, hasLength(30));
  });

  test('default source and cached lists are independent', () async {
    SharedPreferences.setMockInitialValues({
      'announcements.list.cache': jsonEncode([
        const AnnouncementListItem(
          title: '官网旧缓存',
          url: 'https://www.shu.edu.cn/old.htm',
        ).toJson(),
      ]),
    });
    final api = _FakeAnnouncementApiClient();
    final repository = AnnouncementRepository(apiClient: api);
    expect(
        (await repository.loadCachedAnnouncements(
          source: AnnouncementSource.official,
        ))
            .single
            .title,
        '官网旧缓存');

    final bksy = AnnouncementSource.byId('bksy');
    await repository.setDefaultSource(bksy);
    await repository.fetchAnnouncements();
    expect(api.requested, ['bksy']);
    expect((await repository.homeSummary()).text, startsWith('本科生院 · '));
    expect(
        (await repository.loadCachedAnnouncements(
          source: AnnouncementSource.official,
        ))
            .single
            .title,
        '官网旧缓存');
  });

  test('detail previews are queued three at a time and reused', () async {
    final api = _QueuedPreviewApiClient();
    final repository = AnnouncementRepository(apiClient: api);
    final items = List.generate(
      5,
      (index) => AnnouncementListItem(
        title: '公告 $index',
        url: 'https://bksy.shu.edu.cn/info/$index.htm',
        sourceId: 'bksy',
      ),
    );
    final futures = items.map(repository.loadPreview).toList();
    expect(api.requested, hasLength(3));
    final openedDetail = repository.fetchDetail(items.first);
    expect(api.requested, hasLength(3));

    api.complete(items[0].url, '第一条正文摘要');
    expect((await openedDetail).blocks.single.value, '第一条正文摘要');
    await futures[0];
    await Future<void>.delayed(Duration.zero);
    expect(api.requested, hasLength(4));

    for (final item in items.skip(1)) {
      while (!api.requested.contains(item.url)) {
        await Future<void>.delayed(Duration.zero);
      }
      api.complete(item.url, '${item.title}正文');
    }
    await Future.wait(futures);
    expect(await repository.loadPreview(items.first), '第一条正文摘要');
    expect((await repository.fetchDetail(items.first)).blocks.single.value,
        '第一条正文摘要');
    expect(api.requested, hasLength(5));
  });

  test('image-only and PDF announcements use type labels in the list',
      () async {
    final api = _QueuedPreviewApiClient();
    final repository = AnnouncementRepository(apiClient: api);
    const pdf = AnnouncementListItem(
      title: 'PDF 通知',
      url: 'https://cwc.shu.edu.cn/info/pdf.htm',
      sourceId: 'cwc',
    );
    const image = AnnouncementListItem(
      title: '图片通知',
      url: 'https://bksy.shu.edu.cn/info/image.htm',
      sourceId: 'bksy',
    );
    final pdfPreview = repository.loadPreview(pdf);
    final imagePreview = repository.loadPreview(image);
    api.completeBlocks(pdf.url, const [
      AnnouncementContentBlock.image('https://cwc.shu.edu.cn/page.jpg'),
      AnnouncementContentBlock.link(
        'https://cwc.shu.edu.cn/notice.pdf',
        label: '查看原始 PDF',
      ),
    ]);
    api.completeBlocks(image.url, const [
      AnnouncementContentBlock.image('https://bksy.shu.edu.cn/image.jpg'),
    ]);
    expect(await pdfPreview, '[PDF文件]');
    expect(await imagePreview, '[图片]');
  });
}

class _FakeAnnouncementApiClient extends AnnouncementApiClient {
  final requested = <String>[];

  @override
  Future<List<AnnouncementListItem>> fetchAnnouncements({
    AnnouncementSource source = AnnouncementSource.official,
  }) async {
    requested.add(source.id);
    return [
      AnnouncementListItem(
        title: '${source.name}新通知',
        url: '${source.listUrl}/new',
        sourceId: source.id,
      ),
    ];
  }
}

class _QueuedPreviewApiClient extends AnnouncementApiClient {
  final requested = <String>[];
  final pending = <String, Completer<AnnouncementDetail>>{};

  @override
  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) {
    requested.add(item.url);
    final completer = Completer<AnnouncementDetail>();
    pending[item.url] = completer;
    return completer.future;
  }

  void complete(String url, String body) {
    completeBlocks(url, [AnnouncementContentBlock.text(body)]);
  }

  void completeBlocks(String url, List<AnnouncementContentBlock> blocks) {
    pending.remove(url)!.complete(AnnouncementDetail(
          title: '公告',
          url: url,
          blocks: blocks,
        ));
  }
}
