import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/repositories/shuyo_content_repository.dart';
import 'package:shuyo/features/home/shuyo_content_page.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('content repository uses saved list when offline', () async {
    var online = true;
    final client = MockClient((request) async {
      if (!online) throw const ShuyoContentException('offline');
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'success': true,
          'data': [
            {
              'id': 'ann_1',
              'title': '欢迎使用',
              'content': '公告正文',
              'createdAt': '2026-10-08T00:00:00Z',
              'updatedAt': '2026-10-08T00:00:00Z',
            }
          ],
        })),
        200,
      );
    });
    final repository = ShuyoContentRepository(
      client: client,
      baseUrl: 'https://api.shuyo.work',
    );
    final fresh = await repository.load(ShuyoContentKind.announcements);
    expect(fresh.fromCache, isFalse);
    online = false;
    final cached = await repository.load(ShuyoContentKind.announcements);
    expect(cached.fromCache, isTrue);
    expect(cached.items.single.title, '欢迎使用');
  });

  test('old backend returns a clear message without breaking school notices',
      () async {
    final repository = ShuyoContentRepository(
      client: MockClient((request) async => http.Response('', 404)),
      baseUrl: 'https://api.shuyo.work',
    );
    await expectLater(
      repository.load(ShuyoContentKind.tips),
      throwsA(isA<ShuyoContentException>()
          .having((error) => error.message, 'message', contains('暂未提供'))),
    );
  });

  testWidgets('content tabs open details and reject outside images',
      (tester) async {
    final client = MockClient((request) async {
      final tips = request.url.path.endsWith('/tips');
      return http.Response.bytes(
        utf8.encode(jsonEncode({
          'success': true,
          'data': [
            {
              'id': tips ? 'tip_1' : 'ann_1',
              'title': tips ? '快速上手' : '欢迎使用',
              'content': tips
                  ? '# 第一步\n\n![外部图片](https://example.org/image.png)'
                  : '公告正文',
              'createdAt': '2026-10-08T00:00:00Z',
              'updatedAt': '2026-10-08T00:00:00Z',
            }
          ],
        })),
        200,
      );
    });
    final repository = ShuyoContentRepository(
      client: client,
      baseUrl: 'https://api.shuyo.work',
    );
    await tester.pumpWidget(MaterialApp(
      home: ShuyoContentPage(repository: repository),
    ));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用'), findsOneWidget);
    await tester.tap(find.text('欢迎使用'));
    await tester.pumpAndSettle();
    expect(find.text('公告正文'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用提示'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('快速上手'));
    await tester.pumpAndSettle();
    expect(find.text('第一步'), findsOneWidget);
    expect(find.text('图片地址不可用'), findsOneWidget);
  });
}
