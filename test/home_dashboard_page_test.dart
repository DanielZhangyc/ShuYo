import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/home/home_dashboard_page.dart';

void main() {
  Widget page(
          {required bool loggedIn,
          bool syncing = false,
          bool expired = false,
          String? displayName}) =>
      MaterialApp(
        home: Scaffold(
          body: HomeDashboardPage(
            hasAcademicAccount: loggedIn,
            academicSessionExpired: expired,
            academicDisplayName: loggedIn ? displayName ?? '25120000' : null,
            isAcademicLoginCompleting: syncing,
            onLogin: () {},
            onOpenAcademicSystem: () {},
            onOpenAnnouncements: () {},
            onOpenEmptyClassroom: () {},
            todayCourseContent: '今日无课',
            announcementContent: '查看公告',
          ),
        ),
      );

  testWidgets('campus login shows student greeting and campus services',
      (tester) async {
    await tester.pumpWidget(page(loggedIn: true));
    expect(find.text('你好，25120000！'), findsOneWidget);
    expect(find.text('今日课程'), findsOneWidget);
    expect(find.text('空教室查询'), findsOneWidget);
    expect(find.text('图书馆预约'), findsOneWidget);
    expect(find.text('课程评价'), findsNothing);
    expect(find.textContaining('论坛'), findsNothing);
  });

  testWidgets('logged out home invites campus login', (tester) async {
    await tester.pumpWidget(page(loggedIn: false));
    expect(find.text('立即登录'), findsOneWidget);
    expect(find.text('登录后同步个人数据'), findsOneWidget);
  });

  testWidgets('custom nickname changes only the home greeting', (tester) async {
    await tester.pumpWidget(page(loggedIn: true, displayName: '小明'));
    expect(find.text('你好，小明！'), findsOneWidget);
    expect(find.text('你好，25120000！'), findsNothing);
  });

  testWidgets(
      'expired account invites reauthentication while retaining local data',
      (tester) async {
    await tester.pumpWidget(page(loggedIn: false, expired: true));
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.text('登录已失效，本地数据仍可查看'), findsOneWidget);
    expect(find.text('今日无课'), findsOneWidget);
  });
}
