import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';
import 'package:shuyo/shared/widgets/webvpn_toggle.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('account manager distinguishes expiration and restored login',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: false,
        onAcademicLoginCompleted: () {},
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(
      academicLoggedIn: false,
      academicSessionExpired: true,
    );
    await tester.pumpAndSettle();
    expect(find.text('登录已失效'), findsOneWidget);
    expect(find.text('已登录'), findsNothing);
    controller.updateAccountStatus(academicLoggedIn: true);
    await tester.pumpAndSettle();
    expect(find.text('登录已失效'), findsNothing);
    expect(find.text('已登录'), findsOneWidget);
  });

  testWidgets('account manager keeps campus account and WebVPN controls',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: true,
        onAcademicLoginCompleted: () {},
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(
      academicLoggedIn: true,
      webVpnEnabled: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('上大校园账户'), findsOneWidget);
    expect(find.text('使用WebVPN连接'), findsOneWidget);
    expect(find.textContaining('乐乎'), findsNothing);
  });

  testWidgets('pending WebVPN can be retried while its switch is already on',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    var recoveryRequests = 0;
    controller.setWebVpnChangeHandler((enabled) async {
      if (enabled) recoveryRequests++;
      return true;
    });
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: true,
        onAcademicLoginCompleted: () {},
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(
      academicLoggedIn: true,
      webVpnEnabled: true,
      webVpnPendingRecovery: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用WebVPN连接 · 登录待恢复'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('使用WebVPN连接 · 登录待恢复'), const Offset(0, -240));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复WebVPN登录'));
    await tester.pumpAndSettle();
    expect(recoveryRequests, 1);
  });

  testWidgets('account manager shows WebVPN progress below the switch',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    final pending = Completer<bool>();
    controller.setWebVpnChangeHandler((_) => pending.future);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: true,
        onAcademicLoginCompleted: () {},
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(academicLoggedIn: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用WebVPN连接'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('使用WebVPN连接'), const Offset(0, -240));
    await tester.pumpAndSettle();
    final description = find.text('启用后，可使用外部网络访问校内服务');
    final descriptionWidth = tester.getSize(description).width;
    final serviceStatus = find.text('暂时无法获取WebVPN服务状态');
    final statusTop = tester.getTopLeft(serviceStatus).dy;

    await tester.tap(find.descendant(
      of: find.byType(WebVpnToggle),
      matching: find.byType(Switch),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: find.byType(WebVpnToggle),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.descendant(
            of: find.byType(WebVpnToggle),
            matching: find.byType(CircularProgressIndicator),
          ))
          .dy,
      greaterThan(tester.getBottomLeft(find.byType(Switch)).dy),
    );
    expect(tester.getTopLeft(serviceStatus).dy, statusTop);
    expect(
      tester
          .getBottomLeft(find.descendant(
            of: find.byType(WebVpnToggle),
            matching: find.byType(CircularProgressIndicator),
          ))
          .dy,
      lessThan(statusTop),
    );
    expect(tester.getSize(description).width, descriptionWidth);

    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(serviceStatus).dy, statusTop);
  });

  testWidgets('first launch introduces campus features', (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: false,
        initialAcademicLoggedIn: false,
        onAcademicLoginCompleted: () {},
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用ShuYo'), findsOneWidget);
    expect(find.textContaining('乐乎'), findsNothing);
  });
}
