import '../../core/classroom_url_resolver.dart';
import '../../core/webvpn_urls.dart';
import 'session_cookie_jar.dart';

class ClassroomAuthService {
  ClassroomAuthService({
    SessionCookieJar? cookieJar,
    Future<List<SessionCookie>> Function(Uri)? cookieLoader,
  }) : _cookieJar = cookieJar {
    _cookieLoader = cookieLoader ??
        (uri) =>
            (_cookieJar ??= SessionCookieJar.shared).getCookies(domain: uri);
  }

  SessionCookieJar? _cookieJar;
  late final Future<List<SessionCookie>> Function(Uri) _cookieLoader;

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
