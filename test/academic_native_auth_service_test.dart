import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';

void main() {
  test('academic password encryption produces randomized 1024-bit RSA data',
      () {
    final first = AcademicPasswordEncryptor.encrypt('test-password');
    final second = AcademicPasswordEncryptor.encrypt('test-password');

    expect(base64Decode(first), hasLength(128));
    expect(base64Decode(second), hasLength(128));
    expect(second, isNot(first));
  });

  test('sendError explains the rate limit and alternate method', () {
    expect(
      AcademicNativeAuthService.messageForCode('sendError'),
      '验证码发送过于频繁，请切换验证方式或稍后再试',
    );
  });

  group('AcademicSessionCookieStore', () {
    const newsso = 'https://newsso.shu.edu.cn';

    test('keeps WeCom SSO cookies for the newsso callback request', () {
      final store = AcademicSessionCookieStore();

      // 企微扫码流程不经过 login()，SSO 会话 Cookie 需要外部注入。
      store.save(
        Uri.parse('$newsso/oauth/wecom/qrcode'),
        [
          Cookie('SHU_OAUTH2', 'sso-session-value')..path = '/',
          Cookie('empty', '')..path = '/',
        ],
      );

      final header = store.headerFor(Uri.parse(newsso));
      expect(header, 'SHU_OAUTH2=sso-session-value');
      expect(header, isNot(contains('empty=')));
    });

    test('exposes entries for installing into the WebView', () {
      final store = AcademicSessionCookieStore();
      store.save(
        Uri.parse('$newsso/oauth/wecom/qrcode'),
        [Cookie('SHU_OAUTH2', 'sso-session-value')..path = '/'],
      );

      final entry = store.entries.single;
      expect(entry.cookie.name, 'SHU_OAUTH2');
      expect(entry.domain, 'newsso.shu.edu.cn');
      expect(entry.path, '/');
    });

    test('ignores empty cookie values', () {
      final store = AcademicSessionCookieStore();
      store.save(
        Uri.parse('$newsso/oauth/wecom/qrcode'),
        [Cookie('SHU_OAUTH2', '')..path = '/'],
      );
      expect(store.headerFor(Uri.parse(newsso)), isEmpty);
      expect(store.entries, isEmpty);
    });

    test('overwrites a cookie with the same name, domain and path', () {
      final store = AcademicSessionCookieStore();
      final source = Uri.parse('$newsso/oauth/wecom/qrcode');
      store.save(source, [Cookie('SHU_OAUTH2', 'old')..path = '/']);
      store.save(source, [Cookie('SHU_OAUTH2', 'new')..path = '/']);
      expect(store.headerFor(Uri.parse(newsso)), 'SHU_OAUTH2=new');
    });
  });
}
