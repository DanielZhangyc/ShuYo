import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/chaoxing_booking_client.dart';
import 'package:shuyo/data/services/there_booking_client.dart';
import 'package:shuyo/data/services/unified_account_service.dart';
import 'package:shuyo/features/library_booking/library_booking_page.dart';

class _FakeChaoxingBookingClient extends ChaoxingBookingClient {
  _FakeChaoxingBookingClient()
      : super(cookieLoader: (_) async => [], cookieSetter: (_) async {});

  static final _rooms = <Map<String, dynamic>>[
    {
      'id': 'ROOM_QWC',
      'secondLevelName': '钱伟长图书馆',
      'thirdLevelName': '钱伟长二楼阅览室',
      'capacity': 3,
      'startSeatNum': 1,
    },
    {
      'id': 'ROOM_JD',
      'secondLevelName': '嘉定联合馆',
      'thirdLevelName': '嘉定一楼阅览室',
      'capacity': 3,
      'startSeatNum': 1,
    },
    {
      'id': 'ROOM_WH',
      'secondLevelName': '延长文荟馆',
      'thirdLevelName': '文荟三楼阅览室',
      'capacity': 3,
      'startSeatNum': 1,
    },
  ];

  ({String roomId, String start, String end, String seatNum})? submission;

  @override
  Map<String, dynamic>? get user => const {
        'uid': 'USER_1',
        'sno': 'STUDENT_1',
        'uname': '测试用户',
      };

  @override
  Future<Map<String, dynamic>> bootstrap() async => user!;

  @override
  Future<List<Map<String, dynamic>>> rooms() async => _rooms;

  @override
  Future<Map<String, dynamic>> availability({
    required String roomId,
    required String start,
    required String end,
  }) async =>
      {
        'room': _rooms.singleWhere((room) => room['id'] == roomId),
        'available': ['001', '003'],
        'used': ['002'],
        'total': 3,
        'availableCount': 2,
      };

  @override
  Future<String> submit({
    required String roomId,
    required String start,
    required String end,
    required String seatNum,
  }) async {
    submission = (roomId: roomId, start: start, end: end, seatNum: seatNum);
    return '12345';
  }

  @override
  Future<Map<String, dynamic>> home() async => {
        'curReserves': <Map<String, dynamic>>[],
        'nearReserves': <Map<String, dynamic>>[],
      };
}

class _EmptyThereBookingClient extends ThereBookingClient {
  @override
  Future<void> selectVenue(BookingVenue venue) async {}

  @override
  Future<Map<String, dynamic>> profile() async => {
        'id': 'USER_1',
        'loginName': 'STUDENT_1',
        'isAnonymous': false,
      };

  @override
  Future<List<Map<String, dynamic>>> areas(String day) async => [];

  @override
  Future<List<Map<String, dynamic>>> recent() async => [];
}

class _PushObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        AcademicAccountStore.studentIdKey: 'STUDENT_1',
      }));

  const newVenues = <BookingVenue, ({String roomId, String areaName})>{
    BookingVenue.qianweichang: (roomId: 'ROOM_QWC', areaName: '钱伟长二楼阅览室'),
    BookingVenue.jiading: (roomId: 'ROOM_JD', areaName: '嘉定一楼阅览室'),
    BookingVenue.wenhui: (roomId: 'ROOM_WH', areaName: '文荟三楼阅览室'),
  };

  for (final entry in newVenues.entries) {
    testWidgets('${entry.key.label} uses the existing booking steps',
        (tester) async {
      final client = _FakeChaoxingBookingClient();
      final there = _EmptyThereBookingClient();
      final observer = _PushObserver();
      addTearDown(client.dispose);
      addTearDown(there.dispose);
      final today = DateTime.parse(ThereBookingClient.schoolDay());
      DateTime schoolMorning() =>
          DateTime.utc(today.year, today.month, today.day, 8);
      final monthDay = '${today.month}月${today.day}日';

      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: LibraryBookingPage(
          accountService: UnifiedAccountService(),
          thereClientFactory: (_) => there,
          chaoxingClient: client,
          schoolClock: schoolMorning,
        ),
      ));
      await tester.pumpAndSettle();
      final initialPushes = observer.pushes;
      expect(find.text('图书馆预约'), findsOneWidget);

      final campus = switch (entry.key) {
        BookingVenue.jiading => '嘉定校区',
        BookingVenue.wenhui => '延长校区',
        _ => '宝山校区',
      };
      await tester.tap(find.text(campus));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text(entry.key.label), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text(entry.key.label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key.label));
      await tester.pumpAndSettle();
      expect(find.text(entry.value.areaName), findsOneWidget);
      expect(find.text('开放座位数 3'), findsOneWidget);
      expect(find.textContaining('使用中 —'), findsNothing);
      expect(find.textContaining('超星'), findsNothing);

      await tester.tap(find.text(entry.value.areaName));
      await tester.pumpAndSettle();
      expect(find.text('选择日期'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      expect(find.textContaining('明天'), findsNothing);
      expect(find.text(monthDay), findsOneWidget);
      expect(find.textContaining('超星'), findsNothing);

      await tester.tap(find.text(monthDay));
      await tester.pumpAndSettle();
      expect(find.text('选择时间'), findsOneWidget);
      expect(find.textContaining('超星'), findsNothing);

      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      expect(find.text('选择座位'), findsOneWidget);
      expect(find.text('001'), findsOneWidget);
      expect(find.text('002'), findsOneWidget);
      expect(find.textContaining('超星'), findsNothing);
      expect(find.byType(LibraryBookingPage), findsOneWidget);
      expect(observer.pushes, initialPushes,
          reason: 'Selecting a new venue should stay in the existing page');

      await tester.tap(find.text('001'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认预约'));
      await tester.pumpAndSettle();
      expect(find.text('提交'), findsOneWidget);
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      expect(client.submission, isNotNull);
      expect(client.submission!.roomId, entry.value.roomId);
      expect(client.submission!.seatNum, '001');
      expect(client.submission!.start, isNotEmpty);
      expect(client.submission!.end, isNotEmpty);
      expect(find.text('进行中'), findsOneWidget);
      expect(find.textContaining('超星'), findsNothing);
    });
  }
}
