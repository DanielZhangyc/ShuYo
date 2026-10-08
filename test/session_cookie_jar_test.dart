import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/session_cookie_jar.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('returns cookies for the requested host and path scope', () async {
    final jar = SessionCookieJar();
    await jar.setCookie(const SessionCookie(
      name: 'SHU_OAUTH2',
      value: 'sso-session',
      domain: 'newsso.shu.edu.cn',
    ));
    await jar.setCookie(const SessionCookie(
      name: 'JSESSIONID',
      value: 'jwxt-session',
      domain: 'jwxt.shu.edu.cn',
      path: '/jwglxt',
    ));

    final identity = await jar.getCookies(
      domain: Uri.parse('https://newsso.shu.edu.cn/oauth/authorize'),
    );
    expect(identity.map((cookie) => cookie.name), ['SHU_OAUTH2']);

    final menu = await jar.getCookies(
      domain: Uri.parse(
        'https://jwxt.shu.edu.cn/jwglxt/xtgl/index_initMenu.html',
      ),
    );
    expect(menu.map((cookie) => cookie.name), ['JSESSIONID']);

    // A path-scoped cookie must not leak to a request outside its prefix.
    expect(
      await jar.getCookies(domain: Uri.parse('https://jwxt.shu.edu.cn/')),
      isEmpty,
    );
    // Nor may a sibling host inherit another service's identity cookie.
    expect(
      await jar.getCookies(domain: Uri.parse('https://bbs.shu.edu.cn/')),
      isEmpty,
    );
  });

  test('clears only the scope an empty value names', () async {
    final jar = SessionCookieJar();
    const portal = 'webvpn.shu.edu.cn';
    const proxied = 'https-jwxt-shu-edu-cn-443.webvpn.shu.edu.cn';
    await jar.setCookie(
      const SessionCookie(
          name: 'webvpn-token', value: 'portal', domain: portal),
    );
    await jar.setCookie(
      const SessionCookie(
          name: 'webvpn-token', value: 'proxied', domain: proxied),
    );

    await jar.setCookie(
      const SessionCookie(name: 'webvpn-token', value: '', domain: portal),
    );

    expect(
      await jar.getCookies(domain: Uri.parse('https://$portal/site-nav/')),
      isEmpty,
    );
    expect(
      (await jar.getCookies(domain: Uri.parse('https://$proxied/jwglxt/')))
          .single
          .value,
      'proxied',
    );
  });

  test('persists cookies for the next launch', () async {
    final first = SessionCookieJar();
    await first.setCookie(const SessionCookie(
      name: 'webvpn-token',
      value: 'restored-session',
      domain: 'webvpn.shu.edu.cn',
    ));

    final restarted = SessionCookieJar();
    final cookies = await restarted.getCookies(
      domain: Uri.parse('https://webvpn.shu.edu.cn/site-nav/'),
    );

    expect(cookies.single.value, 'restored-session');
  });

  test('accepts the domain forms the platform store used', () async {
    final jar = SessionCookieJar();
    await jar.setCookie(const SessionCookie(
      name: 'route',
      value: 'node-a',
      domain: 'https://jwxt.shu.edu.cn/jwglxt/',
    ));
    await jar.setCookie(const SessionCookie(
      name: 'SHU_OAUTH2',
      value: 'sso-session',
      domain: '.newsso.shu.edu.cn',
    ));

    final academic = await jar.getCookies(
      domain: Uri.parse(
        'https://jwxt.shu.edu.cn/jwglxt/xtgl/index_initMenu.html',
      ),
    );
    expect(academic.single.domain, 'jwxt.shu.edu.cn');
    expect(
      (await jar.getCookies(domain: Uri.parse('https://newsso.shu.edu.cn/')))
          .single
          .domain,
      'newsso.shu.edu.cn',
    );
  });
}
