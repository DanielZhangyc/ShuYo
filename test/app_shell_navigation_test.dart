import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/app/app_shell.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';

void main() {
  testWidgets('keeps four renamed tabs and an empty notification destination',
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
        ['首页', '评教', '地图', '日程']);
    expect(find.text('你好，25120000！'), findsOneWidget);
    for (final label in ['评教', '地图', '日程']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
      expect(find.text(label), findsWidgets);
    }
    await tester.tap(find.byTooltip('通知'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.text('通知'), findsOneWidget);
  });
}
