import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/student_identity_service.dart';
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

  testWidgets('account manager edits nickname and preferred campus',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    controller.updateProfile(
      studentId: '25120000',
      nickname: null,
      preferredCampus: '宝山',
    );
    controller.setProfileChangeHandlers(
      onNicknameChanged: (value) async {
        final nickname = value?.trim();
        controller.updateProfile(
          studentId: '25120000',
          nickname: nickname?.isEmpty == true ? null : nickname,
          preferredCampus: controller.preferredCampus,
        );
        return true;
      },
      onCampusChanged: (campus) async {
        controller.updateProfile(
          studentId: '25120000',
          nickname: controller.nickname,
          preferredCampus: campus,
        );
        return true;
      },
    );
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
    expect(find.text('25120000'), findsOneWidget);
    expect(find.text('校区：宝山'), findsOneWidget);
    final nicknameRect = tester.getRect(find.byKey(const Key('nickname-edit')));
    final campusRect = tester.getRect(find.byKey(const Key('campus-select')));
    expect(campusRect.left - nicknameRect.right, closeTo(16, 1));
    expect((nicknameRect.left + campusRect.right) / 2, closeTo(400, 1));

    await tester.tap(find.byKey(const Key('nickname-edit')));
    await tester.pumpAndSettle();
    expect(find.text('留空将恢复显示学号'), findsNothing);
    await tester.enterText(find.byType(TextFormField), ' 小明 ');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(controller.nickname, '小明');
    expect(controller.academicStudentId, '25120000');
    expect(find.text('小明'), findsOneWidget);

    await tester.tap(find.byKey(const Key('campus-select')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    final campusItem = find.widgetWithText(PopupMenuItem<String>, '嘉定');
    expect(tester.getTopLeft(campusItem).dy,
        greaterThanOrEqualTo(campusRect.bottom));
    await tester.tap(campusItem);
    await tester.pumpAndSettle();
    expect(controller.preferredCampus, '嘉定');
    expect(find.text('校区：嘉定'), findsOneWidget);
  });

  testWidgets('nickname and campus stay on one row on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    controller.updateProfile(
      studentId: '25120000',
      nickname: '一个比较长的昵称用于测试窄屏布局',
      preferredCampus: '宝山东区',
    );
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

    final nicknameRect = tester.getRect(find.byKey(const Key('nickname-edit')));
    final campusRect = tester.getRect(find.byKey(const Key('campus-select')));
    expect(nicknameRect.right, lessThan(campusRect.left));
    expect(nicknameRect.center.dy, closeTo(campusRect.center.dy, 1));
    expect(tester.takeException(), isNull);
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

  testWidgets('new users can defer identity verification after notifications',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = StartupOnboardingController();
    final identity = StudentIdentityService();
    addTearDown(controller.dispose);
    addTearDown(identity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: false,
        initialAcademicLoggedIn: false,
        onAcademicLoginCompleted: () {},
        notificationPermissionRequester: () async => false,
        studentIdentityService: identity,
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('开启通知权限'), findsOneWidget);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('身份验证'), findsOneWidget);
    expect(
      find.text('为避免身份冒用，ShuYo将验证你的校园身份，认证后可使用分享课程表、课程评价等功能。'),
      findsOneWidget,
    );
    expect(tester.getTopLeft(find.text('暂不')).dy,
        lessThan(tester.getTopLeft(find.text('确认')).dy));
    expect(tester.getTopLeft(find.text('隐私政策')).dy,
        greaterThan(tester.getBottomLeft(find.text('确认')).dy));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('暂不'));
    await tester.pumpAndSettle();
    expect(await identity.hasAnsweredConsent(), isTrue);
    expect(await identity.hasConsent(), isFalse);
    expect(find.text('账号管理'), findsOneWidget);
    expect(find.text('上大校园账户'), findsOneWidget);
  });

  testWidgets('existing users get the same identity choice once',
      (tester) async {
    final controller = StartupOnboardingController();
    final identity = StudentIdentityService();
    addTearDown(controller.dispose);
    addTearDown(identity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: false,
        onAcademicLoginCompleted: () {},
        studentIdentityService: identity,
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(academicLoggedIn: false);
    await tester.pumpAndSettle();
    expect(find.text('身份验证'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(await identity.hasConsent(), isTrue);
    expect(find.text('ShuYo 身份'), findsOneWidget);
    expect(find.text('未认证'), findsOneWidget);
    controller.dismissAccountManager();
    await tester.pumpAndSettle();
    controller.openAccountManager(academicLoggedIn: false);
    await tester.pumpAndSettle();
    expect(find.text('身份验证'), findsNothing);
  });

  testWidgets('declining once leaves an account-manager retry entry',
      (tester) async {
    final controller = StartupOnboardingController();
    final identity = StudentIdentityService();
    addTearDown(controller.dispose);
    addTearDown(identity.dispose);
    await tester.pumpWidget(MaterialApp(
      home: StartupOnboarding(
        initiallyCompleted: true,
        initialAcademicLoggedIn: false,
        onAcademicLoginCompleted: () {},
        studentIdentityService: identity,
        controller: controller,
        child: const Scaffold(body: Text('主页')),
      ),
    ));
    controller.openAccountManager(academicLoggedIn: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂不'));
    await tester.pumpAndSettle();
    expect(await identity.hasConsent(), isFalse);
    controller.dismissAccountManager();
    await tester.pumpAndSettle();
    controller.openAccountManager(academicLoggedIn: false);
    await tester.pumpAndSettle();
    expect(find.text('未认证'), findsOneWidget);
    await tester.tap(find.text('未认证'));
    await tester.pumpAndSettle();
    expect(find.text('身份验证'), findsOneWidget);
  });
}
