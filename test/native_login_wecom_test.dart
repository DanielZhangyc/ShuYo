import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/core/wecom_constants.dart';
import 'package:shuyo/data/services/wecom_auth_service.dart';
import 'package:shuyo/features/auth/native_login_page.dart';

/// 企微扫码登录 WebVPN 的产物：握手已在扫码页内完成，回调地址是落地页。
final _webVpnLandingResult = WeComRedeemResult(
  callbackUri: Uri.parse(WeComConstants.webVpnLanding),
  sessionCookies: const [],
);

void main() {
  test('WebVPN WeCom login skips the callback exchange', () {
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.webVpn,
        weComRedeem: _webVpnLandingResult,
      ),
      isTrue,
    );
    // 教务系统的企微流程只拿到授权码，仍须跟随回调兑换会话。
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.academic,
        weComRedeem: _webVpnLandingResult,
      ),
      isFalse,
    );
    // 账密登录不经过扫码页，始终需要兑换回调。
    expect(
      weComEstablishedWebVpnSession(
        destination: NativeLoginDestination.webVpn,
        weComRedeem: null,
      ),
      isFalse,
    );
  });

  testWidgets('campus login shows the WeCom login entry button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeLoginPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用企业微信登录'), findsOneWidget);
  });

  testWidgets('WebVPN login shows the WeCom login entry button',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeLoginPage.webVpn(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('使用企业微信登录'), findsOneWidget);
  });

  testWidgets('booking login names the feature being authorized',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: NativeLoginPage.there()),
    );
    await tester.pumpAndSettle();
    expect(find.text('登录图书馆预约'), findsOneWidget);
    expect(find.text('使用企业微信登录'), findsOneWidget);
  });

  testWidgets(
      'credential card keeps labels and reveals password action on focus',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: NativeLoginPage()));
    await tester.pumpAndSettle();

    final title = tester.getRect(find.text('上大校园账户'));
    final body = tester.getRect(find.byType(SingleChildScrollView));
    expect(title.top, lessThan(body.center.dy - 160));
    expect(find.text('学/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);

    final passwordAction = find.ancestor(
      of: find.byTooltip('显示密码'),
      matching: find.byType(AnimatedOpacity),
    );
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 0);

    await tester.tap(find.byType(TextFormField).last);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 1);

    await tester.enterText(find.byType(TextFormField).first, '123456');
    await tester.pumpAndSettle();
    expect(find.text('学/工号'), findsOneWidget);
    expect(find.text('密码'), findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(passwordAction).opacity, 0);

    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('上大校园账户'));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(tester.takeException(), isNull);
  });
}
