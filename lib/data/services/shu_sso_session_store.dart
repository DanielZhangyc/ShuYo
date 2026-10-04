import 'dart:io';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/wecom_constants.dart';

/// The WebView cookie jar owns the SSO session. Business cookies remain scoped
/// to their own hosts and are never copied onto the identity host.
class ShuSsoSessionStore {
  ShuSsoSessionStore({WebViewCookieManager? cookieManager})
      : _cookieManagerInstance = cookieManager;

  WebViewCookieManager? _cookieManagerInstance;
  WebViewCookieManager get _cookieManager =>
      _cookieManagerInstance ??= WebViewCookieManager();

  static final _identityUri = Uri.parse(WeComConstants.ssoBase);

  Future<List<({Cookie cookie, String domain, String path})>>
      sessionCookies() async {
    final cookies = await _cookieManager.getCookies(domain: _identityUri);
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
        final cookies = await _cookieManager.getCookies(domain: uri);
        for (final cookie in cookies) {
          if (cookie.name != WeComConstants.sessionCookieName) continue;
          await _cookieManager.setCookie(WebViewCookie(
            name: cookie.name,
            value: '',
            domain: cookie.domain.isEmpty
                ? host
                : cookie.domain.replaceFirst(RegExp(r'^\.'), ''),
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
