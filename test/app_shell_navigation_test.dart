import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/app/app_shell.dart';
import 'package:shuyo/features/home/academic_schedule_page.dart';
import 'package:shuyo/features/home/academic_progress_page.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens the schedule from the home row and third tab',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        initialWebVpnEnabled: false,
        selectedThemeId: 'default',
        followSystemTheme: false,
        onThemeChanged: (_) async {},
        onFollowSystemThemeChanged: (_) async {},
        academicLoginSignal: 0,
        initialHasAcademicSession: true,
        initialAcademicStudentId: '25120000',
        onboardingController: controller,
        isDemo: true,
      ),
    ));
    await tester.pumpAndSettle();
    final navigation = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(navigation.items.map((item) => item.label).toList(),
        ['首页', '学业', '日程']);
    expect(find.text('你好，25120000！'), findsOneWidget);
    await tester.tap(find.text('今日课程'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2);
    expect(find.byType(AcademicSchedulePage), findsOneWidget);
    expect(find.byTooltip('课表信息说明'), findsOneWidget);
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('通知'), findsNothing);

    for (final label in ['学业', '首页', '日程']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
              .currentIndex,
          ['首页', '学业', '日程'].indexOf(label));
      if (label == '学业') {
        expect(find.byType(AcademicProgressPage), findsOneWidget);
        expect(find.byTooltip('更多'), findsOneWidget);
      }
    }
    await tester.tap(find.text('首页').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('通知'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('通知'), findsOneWidget);
  });

  testWidgets('starts on the schedule tab for a widget launch', (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: AppShell(
        initialWebVpnEnabled: false,
        selectedThemeId: 'default',
        followSystemTheme: false,
        onThemeChanged: (_) async {},
        onFollowSystemThemeChanged: (_) async {},
        academicLoginSignal: 0,
        initialHasAcademicSession: true,
        initialAcademicStudentId: '25120000',
        onboardingController: controller,
        initialOpenSchedule: true,
        isDemo: true,
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
            .currentIndex,
        2);
    expect(find.byType(AcademicSchedulePage), findsOneWidget);
  });
}
