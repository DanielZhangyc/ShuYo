import 'package:webview_flutter/webview_flutter.dart';

import '../../core/classroom_url_resolver.dart';
import '../../core/webvpn_urls.dart';

class ClassroomAuthService {
  ClassroomAuthService({
    WebViewCookieManager? cookieManager,
    Future<List<WebViewCookie>> Function(Uri)? cookieLoader,
  }) : _cookieManager = cookieManager {
    _cookieLoader = cookieLoader ??
        (uri) =>
            (_cookieManager ??= WebViewCookieManager()).getCookies(domain: uri);
  }

  WebViewCookieManager? _cookieManager;
  late final Future<List<WebViewCookie>> Function(Uri) _cookieLoader;

  Future<String?> cookieHeader() async {
    if (!ClassroomUrlResolver.usesWebVpn) {
      return null;
    }
    final cookies = [
      ...await _cookieLoader(Uri.parse(WebVpnUrls.portal)),
      ...await _cookieLoader(ClassroomUrlResolver.baseUri),
    ];
    final values = <String, String>{};
    for (final cookie in cookies) {
      if (cookie.name.isNotEmpty && cookie.value.isNotEmpty) {
        values[cookie.name] = cookie.value;
      }
    }
    if (values.isEmpty) {
      return null;
    }
    return values.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join('; ');
  }
}
