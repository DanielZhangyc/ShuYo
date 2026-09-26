import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Removes retired forum data while retaining campus services and settings.
class AppDataMigrationService {
  AppDataMigrationService({
    Future<SharedPreferences> Function()? preferencesLoader,
    Future<Directory> Function()? cacheDirectoryLoader,
    WebViewCookieManager? cookieManager,
    Future<List<WebViewCookie>> Function(Uri)? cookieLoader,
    Future<void> Function(WebViewCookie)? cookieSetter,
  })  : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
        _cacheDirectoryLoader =
            cacheDirectoryLoader ?? getApplicationCacheDirectory,
        _cookieManager = cookieManager {
    _cookieLoader = cookieLoader ??
        (uri) =>
            (_cookieManager ??= WebViewCookieManager()).getCookies(domain: uri);
    _cookieSetter = cookieSetter ??
        (cookie) =>
            (_cookieManager ??= WebViewCookieManager()).setCookie(cookie);
  }

  static const currentSchemaVersion = 4;
  static const schemaVersionKey = 'client.data.schema.version';
  static const _forumCookieNames = {
    '_forum_session',
    '_t',
    '_bypass_cache',
    'authentication_data',
  };

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Future<Directory> Function() _cacheDirectoryLoader;
  WebViewCookieManager? _cookieManager;
  late final Future<List<WebViewCookie>> Function(Uri) _cookieLoader;
  late final Future<void> Function(WebViewCookie) _cookieSetter;

  Future<void> migrateIfNeeded() async {
    final preferences = await _preferencesLoader();
    if ((preferences.getInt(schemaVersionKey) ?? 0) >= currentSchemaVersion) {
      return;
    }
    for (final key in preferences.getKeys().toList()) {
      if (key.startsWith('forum.') ||
          key.startsWith('client.backend.presence.day.')) {
        await preferences.remove(key);
      }
    }
    try {
      final root = await _cacheDirectoryLoader();
      final images = Directory('${root.path}/forum-images');
      if (await images.exists()) await images.delete(recursive: true);
      await _clearForumCookies();
    } on Object {
      // Keep startup usable and retry the unfinished cleanup next launch.
      return;
    }
    await preferences.setInt(schemaVersionKey, currentSchemaVersion);
  }

  Future<void> _clearForumCookies() async {
    for (final domain in [
      Uri.parse('https://bbs.shu.edu.cn'),
      Uri.parse('https://https-bbs-shu-edu-cn-443.webvpn.shu.edu.cn'),
    ]) {
      final cookies = await _cookieLoader(domain);
      for (final cookie in cookies) {
        if (!_forumCookieNames.contains(cookie.name)) continue;
        final host = cookie.domain
            .replaceFirst(RegExp(r'^https?://'), '')
            .split('/')
            .first
            .split(':')
            .first;
        await _cookieSetter(
          WebViewCookie(
            name: cookie.name,
            value: '',
            domain: host.isEmpty ? domain.host : host,
            path: cookie.path.isEmpty ? '/' : cookie.path,
          ),
        );
      }
    }
  }
}
