import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/demo/demo_repositories.dart';
import 'package:shuyo/data/models/academic_progress.dart';
import 'package:shuyo/data/repositories/academic_progress_repository.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/academic_progress_api_client.dart';
import 'package:shuyo/data/services/academic_progress_parser.dart';
import 'package:shuyo/features/home/academic_progress_page.dart';

class _AuthWithCookie extends AcademicAuthService {
  _AuthWithCookie()
      : super(
          cookieLoader: (_) async => [],
          cookieSetter: (_) async {},
        );

  @override
  Future<String?> cookieHeader({Uri? targetUri}) async => 'JSESSIONID=test';
}

const _index = '''
<html><body>
<form id="form">
  <input name="xh_id" value="DEMO0001">
  <input name="cjlrxn" value="2026">
  <input name="cjlrxq" value="3">
</form>
<div id="alertBox">（GPA）：3.4 计划总课程 20 门 通过 8 门；未修 10 门；在读 2 门</div>
<ul class="treeview"></ul>
<script>
\$("<li id='limain' fxfyqjd_id='' ><div class='title' xfyqjd_id='main' jdkcsx='' leaf='' sfmjd='0'><p class='title1' id='pmain' yxxf='20' yqzdxf='100' sftg='0'>" +
  "主修&nbsp;" + "</p></div></li>");
\$("<li id='liplan' fxfyqjd_id='main' ><div class='title' xfyqjd_id='plan' jdkcsx='1' leaf='' sfmjd='1'><p class='title1' id='pplan' yxxf='3' yqzdxf='6' sftg='0'>" +
  "计划课程&nbsp;" + "</p></div></li>");
\$("<li id='liother' fxfyqjd_id='main' ><div class='title' xfyqjd_id='other' jdkcsx='4' leaf='' sfmjd='1'><p class='title1' id='pother' yxxf='1' yqzdxf='2' sftg='0'>" +
  "通识课程&nbsp;" + "</p></div></li>");
\$("<li id='liqtkcxfyq' fxfyqjd_id='' ><div class='title' xfyqjd_id='qtkcxfyq' jdkcsx='1' leaf='' sfmjd='1'><p class='title1' id='pqtkcxfyq' yxxf='' yqzdxf='' sftg=''>" +
  "其他课程" + "</p></div></li>");
// zgzsxx 资格证书信息由单独分支生成。
</script></body></html>
''';

void main() {
  test('parses tree, summary and course response', () {
    final index = AcademicProgressParser.parseIndex(_index);
    expect(index.nodes.map((node) => node.name), [
      '主修',
      '计划课程',
      '通识课程',
      '资格证书信息',
      '其他课程',
    ]);
    expect(index.nodes.where((node) => node.isLeaf).length, 4);
    expect(index.gpa, '3.4');
    expect(index.plannedCourses, 20);
    expect(index.passedCourses, 8);
    expect(index.ongoingCourses, 2);
    expect(index.notTakenCourses, 10);

    final courses = AcademicProgressParser.parseCourses(
      '[{"KCH_ID":"C1","KCH":"C1","KCMC":"示例课程",'
      '"XF":"2.0","XDZT":"4","CJ":"90","JD":4}]',
    );
    expect(courses.single.name, '示例课程');
    expect(courses.single.statusLabel, '已修');
    expect(courses.single.gradePoint, '4');
    expect(AcademicProgressParser.parseCertificates('[]'), isEmpty);
    final certificates = AcademicProgressParser.parseCertificates(
      '[{"XMMC":"英语等级考试","SFHD":"已获得"}]',
    );
    expect(certificates.single.name, '英语等级考试');
    expect(certificates.single.acquisitionStatus, '已获得');
  });

  test('fetches each leaf with the matching endpoint and form fields',
      () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'GET') {
        return http.Response.bytes(utf8.encode(_index), 200,
            headers: {'content-type': 'text/html;charset=UTF-8'});
      }
      expect(request.headers['cookie'], 'JSESSIONID=test');
      if (request.url.path.endsWith('cxZgzsInfo.html')) {
        return http.Response('[]', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response.bytes(
        utf8.encode('[{"KCH_ID":"C1","KCH":"C1","KCMC":"示例课程",'
            '"XF":"2.0","XDZT":"1"}]'),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = AcademicProgressApiClient(
      authService: _AuthWithCookie(),
      httpClient: client,
    );

    final progress = await api.fetchProgress();
    expect(progress.nodes.length, 5);
    expect(progress.nodes.where((node) => node.courses.isNotEmpty).length, 3);
    expect(progress.certificates, isEmpty);
    expect(requests.length, 5);
    expect(
        requests
            .where(
                (request) => request.url.path.endsWith('cxJxzxjhxfyqKcxx.html'))
            .length,
        2);
    expect(
        requests
            .where((request) =>
                request.url.path.endsWith('cxJxzxjhxfyqFKcxx.html'))
            .length,
        1);
    final otherCoursesRequest =
        requests.where((request) => request.method == 'POST').singleWhere(
              (request) => request.bodyFields['xfyqjd_id'] == 'qtkcxfyq',
            );
    expect(otherCoursesRequest.bodyFields['cjlrxn'], '2026');
    expect(otherCoursesRequest.bodyFields['cjlrxq'], '3');
    expect(otherCoursesRequest.bodyFields['xh_id'], 'DEMO0001');
    expect(
        requests
            .where((request) => request.url.path.endsWith('cxZgzsInfo.html')),
        hasLength(1));
  });

  testWidgets('browses categories and refreshes from the More menu',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AcademicProgressPage(
        repository: DemoAcademicProgressRepository(),
        onLoginRequired: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('学业总览'), findsOneWidget);
    expect(find.text('公共基础课程'), findsOneWidget);
    await tester.tap(find.text('公共基础课程'));
    await tester.pumpAndSettle();
    expect(find.text('大学英语'), findsOneWidget);
    expect(find.text('已修'), findsOneWidget);
    expect(find.text('在修'), findsOneWidget);
    expect(find.text('待修'), findsOneWidget);
    expect(find.text('公共基础课 · 2.0 学分'), findsOneWidget);
    await tester.tap(find.text('大学英语'));
    await tester.pumpAndSettle();
    expect(find.text('成绩：88'), findsOneWidget);
    Navigator.of(tester.element(find.text('成绩：88'))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('资格证书信息'), 250,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('资格证书信息'));
    await tester.pumpAndSettle();
    expect(find.text('暂无资格证书信息'), findsOneWidget);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(find.text('刷新学业信息'), findsOneWidget);
    await tester.tap(find.text('刷新学业信息'));
    await tester.pumpAndSettle();
    expect(find.text('学业总览'), findsOneWidget);
    expect(find.text('暂无资格证书信息'), findsOneWidget);
  });

  test('does not show another account’s cached progress', () async {
    final sample = DemoAcademicProgressRepository().progress;
    SharedPreferences.setMockInitialValues({
      AcademicProgressRepository.cacheKey: jsonEncode(sample.toJson()),
    });
    final account = AcademicAccountStore();
    await account.saveStudentId('ANOTHER');
    final repository = AcademicProgressRepository();
    expect(await repository.loadCachedProgress(), isNull);
    await account.saveStudentId('DEMO0001');
    expect((await repository.loadCachedProgress())?.studentId, 'DEMO0001');
  });

  test('older cached progress gains the certificate branch', () {
    final oldCache = DemoAcademicProgressRepository().progress.toJson()
      ..remove('certificates');
    (oldCache['nodes'] as List)
        .removeWhere((node) => (node as Map)['id'] == 'zgzsxx');
    final restored = AcademicProgress.fromJson(oldCache);
    expect(restored.node('zgzsxx')?.name, '资格证书信息');
    expect(restored.certificates, isEmpty);
  });

  testWidgets('tree rows fit a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: AcademicProgressPage(
        repository: DemoAcademicProgressRepository(),
        onLoginRequired: () async {},
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('公共基础课程'));
    await tester.pumpAndSettle();
    expect(find.text('大学英语'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
