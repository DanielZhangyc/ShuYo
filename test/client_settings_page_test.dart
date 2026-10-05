import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/repositories/client_backend_repository.dart';
import 'package:shuyo/data/services/academic_schedule_notification_service.dart';
import 'package:shuyo/data/services/academic_schedule_api_client.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/client_settings_service.dart';
import 'package:shuyo/features/settings/client_settings_page.dart';
import 'package:shuyo/features/onboarding/startup_onboarding.dart';
import 'package:shuyo/shared/widgets/webvpn_toggle.dart';
import 'package:shuyo/core/client_app_info.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('settings hides logout entry when no account is active',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ClientSettingsPage(
          settingsService: ClientSettingsService(),
          scheduleNotificationService: AcademicScheduleNotificationService(
            repository: AcademicScheduleRepository(
              apiClient: AcademicScheduleApiClient(
                authService: _FakeAcademicAuthService(),
                httpClient: MockClient(
                  (_) async => http.Response('{}', 200),
                ),
              ),
            ),
          ),
          backendRepository: ClientBackendRepository(),
          selectedThemeId: 'default',
          followSystemTheme: false,
          onThemeChanged: (_) async {},
          onFollowSystemThemeChanged: (_) async {},
          webVpnController: controller,
        ),
      ),
    );

    expect(find.text('退出上大校园账户'), findsNothing);
    expect(find.text('问题与反馈'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('通知设置'), findsNothing);
    expect(find.text('课表提醒'), findsNothing);
    expect(find.text('关于ShuYo'), findsOneWidget);
  });

  testWidgets('WebVPN settings shares the account manager state',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    controller.setWebVpnChangeHandler((enabled) async {
      controller.updateAccountStatus(
        academicLoggedIn: false,
        webVpnEnabled: enabled,
      );
      return true;
    });
    await _pumpSettings(tester, webVpnController: controller);

    expect(tester.getTopLeft(find.text('主题切换')).dy,
        lessThan(tester.getTopLeft(find.text('WebVPN连接')).dy));
    await tester.tap(find.text('WebVPN连接'));
    await tester.pumpAndSettle();
    expect(find.text('WebVPN'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.text('WebVPN'));
    await tester.pumpAndSettle();
    expect(controller.webVpnEnabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    controller.updateAccountStatus(
      academicLoggedIn: false,
      webVpnEnabled: false,
    );
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('WebVPN loading drops below the switch and retracts',
      (tester) async {
    final controller = StartupOnboardingController();
    addTearDown(controller.dispose);
    final pending = Completer<bool>();
    controller.setWebVpnChangeHandler((_) => pending.future);
    await _pumpSettings(tester, webVpnController: controller);
    await tester.tap(find.text('WebVPN连接'));
    await tester.pumpAndSettle();
    final labelWidth = tester.getSize(find.text('WebVPN')).width;

    final loader = find.descendant(
      of: find.byType(WebVpnToggle),
      matching: find.byType(CircularProgressIndicator),
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(loader, findsOneWidget);
    final fallingTop = tester.getTopLeft(loader).dy;
    await tester.pump(const Duration(milliseconds: 200));
    final restingTop = tester.getTopLeft(loader).dy;
    expect(restingTop, greaterThan(fallingTop));
    expect(
        restingTop, greaterThan(tester.getBottomLeft(find.byType(Switch)).dy));
    expect(tester.getSize(find.text('WebVPN')).width, labelWidth);

    pending.complete(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(loader).dy, lessThan(restingTop));
    await tester.pumpAndSettle();
    expect(loader, findsNothing);
  });

  testWidgets('about page exposes project privacy and support information',
      (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('关于ShuYo'));
    await tester.pumpAndSettle();

    expect(
      find.image(const AssetImage('assets/images/icon_light.png')),
      findsOneWidget,
    );
    expect(find.text(ClientAppInfo.appName), findsOneWidget);
    expect(
      find.text(
        '版本 ${ClientAppInfo.version}（${ClientAppInfo.buildNumber}）',
      ),
      findsOneWidget,
    );
    expect(find.text('源代码'), findsOneWidget);
    expect(find.text('GNU General Public License v3.0'), findsOneWidget);
    expect(find.text('第三方开源许可'), findsOneWidget);
    expect(find.text('贡献者'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('检查更新'), 300);
    expect(find.text('权限说明'), findsOneWidget);
    expect(find.text('使用条款'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('问题与反馈'), findsOneWidget);
    expect(find.text('检查更新'), findsOneWidget);
  });

  testWidgets('about page explains Android permissions', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await _pumpSettings(tester);
      await tester.tap(find.text('关于ShuYo'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('权限说明'), 250);
      await tester.tap(find.text('权限说明'));
      await tester.pumpAndSettle();

      expect(find.text('网络访问'), findsOneWidget);
      expect(find.text('通知'), findsOneWidget);
      expect(find.text('精确闹钟'), findsOneWidget);
      expect(find.text('照片与图片'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('开机后恢复提醒'), 200);
      expect(find.text('开机后恢复提醒'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('about page explains iOS-specific permissions', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpSettings(tester);
      await tester.tap(find.text('关于ShuYo'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('权限说明'), 250);
      await tester.tap(find.text('权限说明'));
      await tester.pumpAndSettle();

      expect(find.text('闹钟'), findsOneWidget);
      expect(find.textContaining('AlarmKit'), findsOneWidget);
      expect(find.text('精确闹钟'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(find.text('开机后恢复提醒'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('demo about page hides online support actions', (tester) async {
    await _pumpSettings(tester, isDemo: true);
    await tester.tap(find.text('关于ShuYo'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pumpAndSettle();

    expect(find.text('问题与反馈'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
  });

  testWidgets('WebVPN session alone exposes the logout entry', (tester) async {
    await _pumpSettings(
      tester,
      hasWebVpnSession: true,
      onWebVpnLogout: () async => true,
    );

    expect(find.text('退出登录'), findsOneWidget);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('WebVPN'), findsOneWidget);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  bool isDemo = false,
  bool hasAcademicAccount = false,
  bool hasWebVpnSession = false,
  Future<bool> Function()? onAcademicLogout,
  Future<bool> Function()? onWebVpnLogout,
  StartupOnboardingController? webVpnController,
}) async {
  final controller = webVpnController ?? StartupOnboardingController();
  if (webVpnController == null) addTearDown(controller.dispose);
  await tester.pumpWidget(
    MaterialApp(
      home: ClientSettingsPage(
        settingsService: ClientSettingsService(),
        scheduleNotificationService: AcademicScheduleNotificationService(
          repository: AcademicScheduleRepository(
            apiClient: AcademicScheduleApiClient(
              authService: _FakeAcademicAuthService(),
              httpClient: MockClient((_) async => http.Response('{}', 200)),
            ),
          ),
        ),
        backendRepository: ClientBackendRepository(),
        selectedThemeId: 'default',
        followSystemTheme: false,
        onThemeChanged: (_) async {},
        onFollowSystemThemeChanged: (_) async {},
        webVpnController: controller,
        hasAcademicAccount: hasAcademicAccount,
        hasWebVpnSession: hasWebVpnSession,
        onAcademicLogout: onAcademicLogout,
        onWebVpnLogout: onWebVpnLogout,
        isDemo: isDemo,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeAcademicAuthService implements AcademicAuthService {
  @override
  Future<void> clearAccount({bool sessionExpired = false}) async {}

  @override
  Future<Set<String>> clearCookies() async => {};

  @override
  Future<void> markLoggedIn() async {}

  @override
  Future<String?> cookieHeader({Uri? targetUri}) async => null;

  @override
  Future<bool> hasWebVpnSession() async => false;

  @override
  Future<bool> hasAcademicSession() async => false;

  @override
  Future<WebVpnSessionStatus> validateDirectAcademicSession() async =>
      WebVpnSessionStatus.loginRequired;

  @override
  Future<WebVpnSessionStatus> validateWebVpnSession() async =>
      WebVpnSessionStatus.loginRequired;
}
