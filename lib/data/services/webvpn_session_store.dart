import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/webvpn_urls.dart';
import 'secure_app_store.dart';
import 'session_cookie_jar.dart';

class WebVpnSessionStore {
  WebVpnSessionStore({
    Future<SharedPreferences> Function()? preferencesLoader,
    SecureAppStore? secureStore,
    SessionCookieJar? cookieJar,
    Future<List<SessionCookie>> Function(Uri domain)? cookieLoader,
    Future<void> Function(SessionCookie cookie)? cookieSetter,
  })  : _secureStore =
            secureStore ?? SecureAppStore(preferencesLoader: preferencesLoader),
        _cookieJar = cookieJar ??
            (cookieLoader == null || cookieSetter == null
                ? SessionCookieJar.shared
                : null) {
    _cookieLoader =
        cookieLoader ?? (domain) => _cookieJar!.getCookies(domain: domain);
    _cookieSetter = cookieSetter ?? _cookieJar!.setCookie;
  }

  static const cachedCookiesKey = 'academic.auth.cached_cookies.webvpn';

  final SecureAppStore _secureStore;
  final SessionCookieJar? _cookieJar;
  late final Future<List<SessionCookie>> Function(Uri domain) _cookieLoader;
  late final Future<void> Function(SessionCookie cookie) _cookieSetter;

  Future<void> clearCachedCookiesForReauthentication() async {
    await _secureStore.delete(cachedCookiesKey);
  }

  Future<bool> hasStoredSession() async {
    String? raw;
    try {
      raw = await _secureStore.read(cachedCookiesKey);
    } on Object {
      // Continue with the live cookie if secure storage is unavailable.
    }
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (_containsWebVpnToken(decoded)) return true;
      } on Object {
        // Fall through to the live copy if an older cache is malformed.
      }
    }
    try {
      final cookies = await _cookieLoader(
        Uri.parse(WebVpnUrls.portal),
      );
      return cookies.any(
        (cookie) => cookie.name == 'webvpn-token' && cookie.value.isNotEmpty,
      );
    } on Object {
      return false;
    }
  }

  /// Removes a WebVPN session after an explicit logout or a confirmed gateway
  /// rejection. A transport failure alone must never call this method.
  Future<void> clearSession() async {
    await clearCachedCookiesForReauthentication();

    final domains = <Uri>[
      Uri.parse(WebVpnUrls.portal),
      Uri.parse('https://https-oauth-shu-edu-cn-443.webvpn.shu.edu.cn'),
      Uri.parse('https://https-newsso-shu-edu-cn-443.webvpn.shu.edu.cn'),
    ];
    for (final domain in domains) {
      final isPortalHost = domain.host == Uri.parse(WebVpnUrls.portal).host;
      final isProxiedIdentityHost = domain.host.contains('oauth-shu-edu-cn') ||
          domain.host.contains('newsso-shu-edu-cn');
      List<SessionCookie> cookies;
      try {
        cookies = await _cookieLoader(domain);
      } on Object {
        continue;
      }
      for (final cookie in cookies) {
        // Never clear a name on a host that does not own it. An empty
        // webvpn-token written to a proxy subdomain would drop a session the
        // next login still needs.
        final belongsToWebVpnSession =
            (isPortalHost && cookie.name == 'webvpn-token') ||
                (isProxiedIdentityHost && cookie.name == 'SHU_OAUTH2');
        if (!belongsToWebVpnSession) continue;
        try {
          await _cookieSetter(
            SessionCookie(
              name: cookie.name,
              value: '',
              domain: _normalizeCookieDomain(cookie.domain, domain.host),
              path: cookie.path.isEmpty ? '/' : cookie.path,
            ),
          );
        } on Object {
          // The persistent copy is already gone. Continue clearing the other
          // known gateway domains even if one cookie write fails.
        }
      }
    }
  }

  String _normalizeCookieDomain(String value, String fallbackHost) {
    if (value.isEmpty) return fallbackHost;
    final parsed = Uri.tryParse(value);
    if (parsed != null && parsed.host.isNotEmpty) return parsed.host;
    final withoutScheme = value.replaceFirst(RegExp(r'^https?://'), '');
    final host = withoutScheme.split('/').first.split(':').first;
    return host.isEmpty ? fallbackHost : host;
  }

  bool _containsWebVpnToken(Object? value) {
    if (value is Map) {
      if (value['name'] == 'webvpn-token' &&
          value['value']?.toString().isNotEmpty == true) {
        return true;
      }
      return value.values.any(_containsWebVpnToken);
    }
    if (value is Iterable) return value.any(_containsWebVpnToken);
    return false;
  }
}
