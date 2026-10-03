import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/there_booking_client.dart';
import 'package:shuyo/data/services/unified_account_service.dart';
import 'package:shuyo/features/library_booking/library_booking_page.dart';

class _BookingClient extends ThereBookingClient {
  _BookingClient()
      : super(cookieLoader: (_) async => [], cookieSetter: (_) async {});

  final selectedVenues = <BookingVenue>[];
  bool created = false;
  bool cancelled = false;

  @override
  Future<void> selectVenue(BookingVenue venue) async {
    selectedVenues.add(venue);
  }

  @override
  Future<Map<String, dynamic>> profile() async => {
        'id': 'USER_1',
        'name': '测试用户',
        'loginName': 'STUDENT_1',
        'isAnonymous': false,
      };

  @override
  Future<List<Map<String, dynamic>>> recent() async => created
      ? [
          {
            'id': 'BOOKING_1',
            'roomType': BookingVenue.library.roomType,
            'roomName': '2E015',
            'officeAreaName': '二楼东侧',
            'beginTime': '2026-10-03 08:30:00',
            'endTime': '2026-10-03 09:30:00',
            'statusLabel': cancelled ? '已取消' : '已预约',
          },
        ]
      : [];

  @override
  Future<Map<String, dynamic>> overview(String day) async => {
        'bookingDays': [
          {'day': '2026-10-03'},
        ],
      };

  @override
  Future<List<Map<String, dynamic>>> areas(String day) async => [
        {
          'id': 'AREA_1',
          'name': '二楼东侧',
          'parentId': 'ROOT',
          'supportRoomTypes': [
            for (final venue in BookingVenue.values) venue.roomType,
          ],
        },
      ];

  @override
  Future<Map<String, dynamic>> area(
          String areaId, String begin, String end) async =>
      {
        'bookingTimes': {
          'suggestStartTime': '08:30',
          'suggestEndTime': '09:30',
          'minDuration': 30,
          'maxDuration': 480,
        },
        'rooms': [
          {
            'id': 'ROOM_1',
            'name': '2E015',
            'officeAreaId': 'AREA_1',
            'abilities': ['booking'],
          },
        ],
      };

  @override
  Future<String> create({
    required String areaId,
    required String roomId,
    required String day,
    required String start,
    required String end,
  }) async {
    created = true;
    return 'BOOKING_1';
  }

  @override
  Future<Map<String, dynamic>> detail(String bookingId) async => {
        'id': bookingId,
        'roomName': '2E015',
        'allOfficeAreaName': '校本部图书馆-二楼东侧',
        'beginTime': '2026-10-03 08:30:00',
        'endTime': '2026-10-03 09:30:00',
        'statusLabel': cancelled ? '已取消' : '已预约',
        'abilities': cancelled ? <String>[] : ['cancel'],
      };

  @override
  Future<void> cancel(String bookingId) async {
    cancelled = true;
  }
}

class _UnreachableBookingClient extends _BookingClient {
  @override
  Future<void> selectVenue(BookingVenue venue) async =>
      throw const ThereBookingException(
        ThereFailureKind.unreachable,
        '暂时无法访问预约系统。请连接校园网、学校VPN，或开启WebVPN后重试。',
      );
}

class _GatewayRecoveryClient extends _BookingClient {
  bool gatewayLoginRequired = true;

  @override
  Future<void> selectVenue(BookingVenue venue) async {
    if (gatewayLoginRequired) {
      throw const ThereBookingException(
        ThereFailureKind.webVpnLoginRequired,
        'WebVPN登录已失效',
      );
    }
    await super.selectVenue(venue);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'four venues, create confirmation, and cancellation are reachable',
      (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('图书馆预约'), findsOneWidget);
    for (final venue in BookingVenue.values) {
      expect(find.text(venue.label), findsWidgets);
    }
    await tester.ensureVisible(find.text('2E015'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2E015'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('确认预约'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('确认预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(client.created, isTrue);
    expect(find.text('取消预约'), findsOneWidget);
    await tester.tap(find.text('取消预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认取消'));
    await tester.pumpAndSettle();
    expect(client.cancelled, isTrue);
  });

  testWidgets('unreachable campus service suggests campus network',
      (tester) async {
    final client = _UnreachableBookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('请连接校园网、学校VPN，或开启WebVPN后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
  });

  testWidgets('proxy page restores gateway before reading bookings',
      (tester) async {
    final client = _GatewayRecoveryClient();
    addTearDown(client.dispose);
    var recoveries = 0;
    await tester.pumpWidget(MaterialApp(
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
        useWebVpn: true,
        onWebVpnSessionRequired: () async {
          recoveries++;
          client.gatewayLoginRequired = false;
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(recoveries, 1);
    expect(find.text('预约座位'), findsOneWidget);
  });
}
