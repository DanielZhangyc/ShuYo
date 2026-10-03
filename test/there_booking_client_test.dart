import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/services/there_booking_client.dart';

void main() {
  late HttpServer server;
  late StreamSubscription<HttpRequest> requests;
  late ThereBookingClient client;
  final seen = <String>[];
  final requestCookies = <String, String?>{};
  final mobileModes = <String>[];
  Map<String, dynamic>? createdBody;
  var rejected = false;
  var requireLogin = false;
  var redirectLocation = '/login?code=SECRET_AUTH_CODE';
  var weChatRedirectForMarked = false;
  var weChatRedirectForAll = false;

  setUp(() async {
    seen.clear();
    requestCookies.clear();
    mobileModes.clear();
    createdBody = null;
    rejected = false;
    requireLogin = false;
    redirectLocation = '/login?code=SECRET_AUTH_CODE';
    weChatRedirectForMarked = false;
    weChatRedirectForAll = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = server.listen((request) async {
      final path = request.uri.path;
      final method = request.method;
      seen.add('$method $path '
          '${request.headers.value('x-room-type') ?? '-'} '
          '${request.headers.value('x-hys-session') ?? '-'}');
      requestCookies[path] = request.headers.value(HttpHeaders.cookieHeader);
      Object response;
      if (path == '/login') {
        request.response.statusCode = 302;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/oauth2/login/context');
        request.response.headers
            .add(HttpHeaders.setCookieHeader, 'SPHYS_SESSION=prewarm; Path=/');
        response = '';
      } else if (path == '/login-oauth2') {
        request.response.statusCode = 302;
        request.response.headers
            .set(HttpHeaders.locationHeader, '/web?authJump=token');
        request.response.headers.add(
            HttpHeaders.setCookieHeader, 'SPHYS_SESSION=authenticated; Path=/');
        response = '';
      } else if (path == '/web') {
        response = '<html>空间预约</html>';
      } else if (path == '/mobile/libseat' || path == '/mobile/seat2021') {
        final marked =
            request.headers.value('x-requested-with') == 'com.tencent.wework';
        mobileModes.add(marked ? 'wework-header' : 'plain');
        if (weChatRedirectForAll || (weChatRedirectForMarked && marked)) {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader,
              'https://open.weixin.qq.com/connect/oauth2/authorize?code=SECRET_AUTH_CODE');
          await request.response.close();
          return;
        }
        if (requireLogin) {
          request.response.statusCode = 302;
          request.response.headers
              .set(HttpHeaders.locationHeader, redirectLocation);
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.html;
        response = path == '/mobile/libseat'
            ? 'window.loginUser={"isAnonymous":false};'
                'window.sessionId="SESSION_LIB";'
            : 'window.loginUser={"isAnonymous":false,'
                '"sessionId":"SESSION_24H"};';
      } else if (path == '/api/v3/my/profile') {
        response = {
          'code': 0,
          'data': {
            'id': 'USER_1',
            'name': '测试用户',
            'loginName': 'STUDENT_1',
            'isAnonymous': false,
          },
        };
      } else if (path == '/api/v3/booking-status/areas/AREA_1') {
        response = {
          'code': 0,
          'data': {
            'bookingTimes': {'supportAcrossDayBooking': false},
            'rooms': [
              {
                'id': 'ROOM_1',
                'name': '2E015',
                'officeAreaId': 'AREA_1',
                'disabled': false,
                'isBusy': false,
                'isBooked': false,
                'abilities': ['booking'],
              },
            ],
          },
        };
      } else if (path == '/api/v3/bookings' && method == 'POST') {
        createdBody = jsonDecode(await utf8.decodeStream(request))
            as Map<String, dynamic>;
        response = rejected
            ? {'code': 200, 'warnMessage': '超过预约天数'}
            : {
                'code': 0,
                'data': [
                  {'id': 'BOOKING_1'},
                ],
              };
      } else if (path == '/api/v3/bookings/BOOKING_1') {
        response = {
          'code': 0,
          'data': {
            'id': 'BOOKING_1',
            'abilities': request.headers.value('x-room-type') == 'STATION'
                ? ['close']
                : ['cancel'],
          },
        };
      } else if (path == '/api/v3/bookings/BOOKING_1/cancel') {
        response = {'code': 0, 'data': {}};
      } else if (path == '/api/v3/bookings/BOOKING_1/finish') {
        response = {'code': 0, 'data': {}};
      } else {
        request.response.statusCode = 404;
        response = {'error': 'unhandled'};
      }
      request.response.write(
        response is String ? response : jsonEncode(response),
      );
      await request.response.close();
    });
    client = ThereBookingClient(
      serviceUri: Uri.parse('http://127.0.0.1:${server.port}'),
      cookieLoader: (_) async => [],
      cookieSetter: (_) async {},
    );
  });

  tearDown(() async {
    client.dispose();
    await requests.cancel();
    await server.close(force: true);
  });

  test('each venue uses its own mobile session and room type', () async {
    await client.selectVenue(BookingVenue.library);
    await client.profile();
    await client.selectVenue(BookingVenue.studySpace);
    await client.profile();
    expect(seen, contains('GET /api/v3/my/profile LIB_SEAT SESSION_LIB'));
    expect(seen, contains('GET /api/v3/my/profile STATION SESSION_24H'));
  });

  test('create rechecks the seat and cancel checks detail ability', () async {
    await client.selectVenue(BookingVenue.library);
    final id = await client.create(
      areaId: 'AREA_1',
      roomId: 'ROOM_1',
      day: '2026-10-03',
      start: '08:30',
      end: '09:30',
    );
    expect(id, 'BOOKING_1');
    expect(createdBody?['subject'], '测试用户');
    expect(createdBody?['meetingMembers'], ['USER_1']);
    expect((createdBody?['rooms'] as List).single['id'], 'ROOM_1');
    expect(seen, contains('POST /api/v3/bookings LIB_SEAT SESSION_LIB'));
    await client.cancel(id);
    expect(
        seen,
        contains('DELETE /api/v3/bookings/BOOKING_1/cancel '
            'LIB_SEAT SESSION_LIB'));
  });

  test('HTTP 200 with a rejected business code is not success', () async {
    rejected = true;
    await client.selectVenue(BookingVenue.library);
    await expectLater(
      client.create(
        areaId: 'AREA_1',
        roomId: 'ROOM_1',
        day: '2026-10-03',
        start: '08:30',
        end: '09:30',
      ),
      throwsA(isA<ThereBookingException>().having(
        (error) => error.message,
        'message',
        '超过预约天数',
      )),
    );
    expect(seen.where((entry) => entry.startsWith('POST /api/v3/bookings')),
        hasLength(1));
  });

  test('24H early finish is only sent when detail allows close', () async {
    await client.selectVenue(BookingVenue.studySpace);
    await client.finish('BOOKING_1');
    expect(
        seen,
        contains('PUT /api/v3/bookings/BOOKING_1/finish '
            'STATION SESSION_24H'));
  });

  test('there bootstrap cookie is carried through OAuth callback', () async {
    await client.prepareOAuth();
    await client.completeOAuth(
        Uri.parse('http://127.0.0.1:${server.port}/login-oauth2?code=ONCE'));
    expect(requestCookies['/login-oauth2'], contains('SPHYS_SESSION=prewarm'));
    expect(requestCookies['/web'], contains('SPHYS_SESSION=authenticated'));
    expect(await client.profile(), containsPair('id', 'USER_1'));
  });

  test('HTTP there landing is upgraded to HTTPS without changing its token',
      () {
    final secureClient = ThereBookingClient(
      cookieLoader: (_) async => [],
      cookieSetter: (_) async {},
    );
    addTearDown(secureClient.dispose);
    final landing = secureClient.normalizeServiceRedirect(Uri.parse(
      'http://there.shu.edu.cn/web?authJump=SECRET_TOKEN',
    ));
    expect(landing?.origin, 'https://there.shu.edu.cn');
    expect(landing?.path, '/web');
    expect(landing?.queryParameters['authJump'], 'SECRET_TOKEN');
    expect(
      secureClient.normalizeServiceRedirect(
          Uri.parse('http://other.shu.edu.cn/web?authJump=SECRET_TOKEN')),
      isNull,
    );
    expect(
      secureClient.normalizeServiceRedirect(
          Uri.parse('http://there.shu.edu.cn:8080/web')),
      isNull,
    );
  });

  test('there callback diagnostics redact the code and landing token',
      () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previous);
    await client.prepareOAuth();
    await client.completeOAuth(Uri.parse(
        'http://127.0.0.1:${server.port}/login-oauth2?code=SECRET_CODE'));
    final log = logs.join('\n');
    expect(log, contains('oauth-stage path=/login-oauth2 status=302'));
    expect(log, isNot(contains('SECRET_CODE')));
    expect(log, isNot(contains('authJump=token')));
  });

  test('account matching accepts either loginName or jobNumber', () {
    expect(
      ThereBookingClient.matchesAccount(
          {'loginName': 'internal', 'jobNumber': 'STUDENT_1'}, 'student_1'),
      isTrue,
    );
    expect(
      ThereBookingClient.matchesAccount(
          {'loginName': 'ANOTHER', 'jobNumber': 'OTHER'}, 'STUDENT_1'),
      isFalse,
    );
  });

  test('an explicit login redirect is classified separately from an outage',
      () async {
    requireLogin = true;
    await expectLater(
      client.selectVenue(BookingVenue.library),
      throwsA(isA<ThereBookingException>().having(
        (error) => error.kind,
        'kind',
        ThereFailureKind.loginRequired,
      )),
    );
  });

  test('WeCom-only mobile redirect retries once as a plain app request',
      () async {
    weChatRedirectForMarked = true;
    await client.selectVenue(BookingVenue.library);
    expect(await client.profile(), containsPair('id', 'USER_1'));
    expect(mobileModes, ['wework-header', 'plain']);
  });

  test('a persistent WeChat redirect tries SSO before reporting a gap',
      () async {
    weChatRedirectForAll = true;
    await expectLater(
      client.selectVenue(BookingVenue.library),
      throwsA(isA<ThereBookingException>().having(
          (error) => error.kind, 'kind', ThereFailureKind.loginRequired)),
    );
    await client.prepareOAuth();
    await expectLater(
      client.completeOAuth(
          Uri.parse('http://127.0.0.1:${server.port}/login-oauth2?code=ONCE')),
      throwsA(isA<ThereBookingException>()
          .having((error) => error.kind, 'kind', ThereFailureKind.uncertain)
          .having((error) => error.message, 'message', contains('微信授权'))),
    );
    expect(mobileModes, ['wework-header', 'plain', 'wework-header', 'plain']);
  });

  test('mobile entry log reports status without redirect secrets', () async {
    final logs = <String>[];
    final previous = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = previous);
    requireLogin = true;
    await expectLater(
      client.selectVenue(BookingVenue.library),
      throwsA(isA<ThereBookingException>()),
    );
    final log =
        logs.where((line) => line.contains('[THERE_BOOKING]')).join('\n');
    expect(log, contains('status=302'));
    expect(log, contains('redirect=http://127.0.0.1/login'));
    expect(log, isNot(contains('SECRET_AUTH_CODE')));
    expect(log, isNot(contains('code=')));
    redirectLocation = '/callback/SHORT_SECRET?code=SECRET_AUTH_CODE';
    await expectLater(
      client.selectVenue(BookingVenue.library),
      throwsA(isA<ThereBookingException>()),
    );
    expect(logs.join('\n'), isNot(contains('SHORT_SECRET')));
  });
}
