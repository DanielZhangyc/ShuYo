import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/features/auth/native_login_page.dart';

void main() {
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

  testWidgets('forum login shows the WeCom login entry button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NativeLoginPage.forum(),
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
}
