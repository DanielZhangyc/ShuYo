import 'dart:io';

import '../../core/wecom_constants.dart';
import 'session_cookie_jar.dart';

/// The session cookie jar owns the SSO session. Business cookies remain scoped
/// to their own hosts and are never copied onto the identity host.
class ShuSsoSessionStore {
  ShuSsoSessionStore({SessionCookieJar? cookieJar})
      : _cookieJarInstance = cookieJar;

  SessionCookieJar? _cookieJarInstance;
  SessionCookieJar get _cookieJar =>
      _cookieJarInstance ??= SessionCookieJar.shared;

  static final _identityUri = Uri.parse(WeComConstants.ssoBase);

  Future<List<({Cookie cookie, String domain, String path})>>
      sessionCookies() async {
    final cookies = await _cookieJar.getCookies(domain: _identityUri);
    return [
      for (final cookie in cookies)
        if (cookie.name == WeComConstants.sessionCookieName &&
            cookie.value.isNotEmpty)
          (
            cookie: Cookie(cookie.name, cookie.value)
              ..domain = _identityUri.host
              ..path = cookie.path.isEmpty ? '/' : cookie.path,
            domain: _identityUri.host,
            path: cookie.path.isEmpty ? '/' : cookie.path,
          ),
    ];
  }

  Future<void> clearSession() async {
    var failed = false;
    for (final host in [
      _identityUri.host,
      'oauth.shu.edu.cn',
      WeComConstants.webVpnNewssoProxyHost,
      'https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn',
    ]) {
      try {
        final uri = Uri(scheme: 'https', host: host);
        final cookies = await _cookieJar.getCookies(domain: uri);
        for (final cookie in cookies) {
          if (cookie.name != WeComConstants.sessionCookieName) continue;
          await _cookieJar.setCookie(SessionCookie(
            name: cookie.name,
            value: '',
            domain: cookie.domain.isEmpty ? host : cookie.domain,
            path: cookie.path.isEmpty ? '/' : cookie.path,
          ));
        }
      } on Object {
        failed = true;
      }
    }
    if (failed) throw StateError('部分统一认证 Cookie 未能清除');
  }
}
