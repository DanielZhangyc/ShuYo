import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/there_booking_client.dart';
import 'package:shuyo/data/services/unified_account_service.dart';
import 'package:shuyo/features/library_booking/library_booking_page.dart';
import 'package:shuyo/features/library_booking/library_booking_resources.dart';
import 'package:shuyo/shared/navigation/shuyo_route.dart';
import 'package:shuyo/shared/theme/custom_background.dart';
import 'package:shuyo/shared/theme/shuyo_theme.dart';

class _BookingClient extends ThereBookingClient {
  _BookingClient()
      : super(cookieLoader: (_) async => [], cookieSetter: (_) async {});

  final selectedVenues = <BookingVenue>[];
  int areaListCalls = 0;
  int detailAreaCalls = 0;
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
          {'day': day},
        ],
      };

  @override
  Future<List<Map<String, dynamic>>> areas(String day) async {
    areaListCalls++;
    return [
      {
        'id': 'ROOT',
        'name': '校本部图书馆自修区',
        'supportRoomTypes': [BookingVenue.library.roomType],
      },
      {
        'id': 'AREA_1',
        'name': '二楼东侧',
        'parentId': 'ROOT',
        'totalResourceCount': 10,
        'disabledResourceCount': 1,
        'busyResourceCount': 3,
        'freeResourceCount': 6,
        'bookingTimes': {'startHour': 8, 'endHour': 22},
        'supportRoomTypes': [
          for (final venue in BookingVenue.values) venue.roomType,
        ],
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> area(
      String areaId, String begin, String end) async {
    if (begin.contains(' ')) detailAreaCalls++;
    return {
      'bookingTimes': {
        'suggestStartTime': '08:30',
        'suggestEndTime': '09:30',
        'minDuration': 30,
        'maxDuration': 480,
        'startHour': 8,
        'endHour': 22,
        'meetingInterval': 30,
      },
      'rooms': [
        {
          'id': 'ROOM_1',
          'name': '2E015',
          'officeAreaId': 'AREA_1',
          'abilities': ['booking'],
        },
        {
          'id': 'ROOM_2',
          'name': '2E016',
          'officeAreaId': 'AREA_1',
          'isBusy': true,
          'abilities': <String>[],
        },
      ],
    };
  }

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

class _HistoryClient extends _BookingClient {
  @override
  Future<List<Map<String, dynamic>>> recent() async {
    final tomorrow = DateTime.parse(ThereBookingClient.schoolDay())
        .add(const Duration(days: 1));
    final day =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    return [
      {
        'id': 'UPCOMING',
        'roomType': BookingVenue.studySpace.roomType,
        'roomName': 'B-034',
        'officeAreaName': 'B',
        'beginTime': '$day 08:30:00',
        'endTime': '$day 09:30:00',
        'status': cancelled ? 'CANCEL' : 'NORMAL',
        'statusLabel': cancelled ? '已取消' : '正常',
      },
      {
        'id': 'FINISHED_EARLY',
        'roomType': BookingVenue.studySpace.roomType,
        'roomName': 'A-001',
        'officeAreaName': 'A',
        'beginTime': '2026-01-01 08:30:00',
        'endTime': '2026-01-01 08:30:00',
        'origEndAt': '2026-01-01 09:30:00',
        'duration': 0,
        'status': 'CANCEL',
        'statusLabel': '已取消',
      },
    ];
  }
}

class _ManyDaysClient extends _BookingClient {
  @override
  Future<Map<String, dynamic>> overview(String day) async {
    final today = DateTime.parse(day);
    String format(DateTime value) => '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
    return {
      'bookingDays': [
        for (var offset = 0; offset < 4; offset++)
          {
            'day': format(
                DateTime.utc(today.year, today.month, today.day + offset))
          },
      ],
    };
  }
}

class _NoMinimumClient extends _BookingClient {
  @override
  Future<Map<String, dynamic>> area(
      String areaId, String begin, String end) async {
    final data = await super.area(areaId, begin, end);
    (data['bookingTimes'] as Map).remove('minDuration');
    return data;
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('custom photo travels with each booking step', (tester) async {
    SharedPreferences.setMockInitialValues({
      AcademicAccountStore.studentIdKey: 'STUDENT_1',
    });
    const background = CustomBackground(
      imagePath: 'assets/images/icon.png',
      opacity: 50,
      background: Color(0xFFF8F8F8),
      surface: Colors.white,
      text: Color(0xFF171717),
      accent: Color(0xFF3478D4),
    );
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: background.theme.themeData(),
      builder: (_, child) => CustomBackgroundFrame(
        settings: background,
        child: child!,
      ),
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
        schoolClock: () {
          final day = DateTime.parse(ThereBookingClient.schoolDay());
          return DateTime.utc(day.year, day.month, day.day, 8);
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ShuYoRouteSurface), findsOneWidget);

    await tester.tap(find.text('仅查看座位情况'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(ShuYoRouteSurface), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(ShuYoRouteSurface),
        matching: find.byType(CustomBackgroundLayer),
      ),
      findsNWidgets(2),
    );
  });

  DateTime schoolMorning() {
    final day = DateTime.parse(ThereBookingClient.schoolDay());
    return DateTime.utc(day.year, day.month, day.day, 8);
  }

  String monthDay() {
    final date = DateTime.parse(ThereBookingClient.schoolDay());
    return '${date.month}月${date.day}日';
  }

  Future<void> pickTime(
      WidgetTester tester, String box, String hour, String minute) async {
    await tester.tap(find.byKey(ValueKey(box)));
    await tester.pumpAndSettle();
    int indexFor(String title, String value) {
      final picker = tester
          .widget<CupertinoPicker>(find.byKey(ValueKey('time-wheel-$title')));
      final children =
          (picker.childDelegate as ListWheelChildListDelegate).children;
      return children.indexWhere(
          (child) => ((child as Center).child as Text).data == value);
    }

    final hourPicker = tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('time-wheel-小时')));
    final hourIndex = indexFor('小时', hour);
    expect(hourIndex, greaterThanOrEqualTo(0));
    hourPicker.scrollController!.jumpToItem(hourIndex);
    await tester.pumpAndSettle();
    final minutePicker = tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('time-wheel-分钟')));
    final minuteIndex = indexFor('分钟', minute);
    expect(minuteIndex, greaterThanOrEqualTo(0));
    minutePicker.scrollController!.jumpToItem(minuteIndex);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认时间'));
    await tester.pumpAndSettle();
  }

  String boxValue(WidgetTester tester, String key) => tester
      .widget<Text>(
        find.descendant(
            of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
      )
      .data!;

  testWidgets(
      'four venues, create confirmation, and cancellation are reachable',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      AcademicAccountStore.studentIdKey: 'STUDENT_1',
    });
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
        schoolClock: schoolMorning,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('图书馆预约'), findsOneWidget);
    expect(find.text('暂无本地记录'), findsOneWidget);
    for (final venue in BookingVenue.values) {
      expect(find.text(venue.label), findsWidgets);
    }
    await tester.tap(find.text('我的预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回上一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    expect(find.byTooltip('我的预约'), findsNothing);
    expect(find.text('以下为当前座位情况'), findsNothing);
    expect(find.text('校本部图书馆自修区 - 二楼东侧'), findsOneWidget);
    expect(find.textContaining('开放座位数 9'), findsOneWidget);
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    expect(find.textContaining(ThereBookingClient.schoolDay()), findsNothing);
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(find.textContaining(ThereBookingClient.schoolDay()), findsNothing);
    expect(find.textContaining('最长 8 小时'), findsOneWidget);
    expect(client.detailAreaCalls, 0);
    expect(boxValue(tester, 'start-hour'), '08');
    expect(boxValue(tester, 'start-minute'), '00');
    expect(boxValue(tester, 'end-hour'), '10');
    expect(boxValue(tester, 'end-minute'), '00');
    await pickTime(tester, 'start-hour', '10', '00');
    await pickTime(tester, 'end-minute', '11', '00');
    expect(boxValue(tester, 'start-hour'), '10');
    expect(boxValue(tester, 'end-hour'), '11');
    expect(client.detailAreaCalls, 0);
    final nextPosition = tester.getTopLeft(find.text('下一步'));
    await tester.tap(find.text('预览可选座位数'));
    await tester.pumpAndSettle();
    expect(find.text('可选 1 个'), findsOneWidget);
    expect(tester.getTopLeft(find.text('下一步')), nextPosition);
    expect(client.detailAreaCalls, 1);
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(client.detailAreaCalls, 2);
    expect(find.textContaining(ThereBookingClient.schoolDay()), findsNothing);
    await tester.tap(find.text('2E015'));
    await tester.pumpAndSettle();
    final selectedWeight =
        tester.widget<Text>(find.text('2E015')).style!.fontWeight;
    await tester.tap(find.text('2E015'));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.text('2E015')).style!.fontWeight,
        selectedWeight);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '确认预约'))
            .onPressed,
        isNull);
    await tester.tap(find.text('2E015'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交'));
    await tester.pumpAndSettle();
    expect(client.created, isTrue);
    expect(client.selectedVenues.last, BookingVenue.library);
    expect(find.text('取消预约'), findsOneWidget);
    await tester.tap(find.text('取消预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.cancelled, isTrue);
    for (var step = 0; step < 4; step++) {
      await tester.tap(find.byTooltip('返回上一步'));
      await tester.pumpAndSettle();
    }
    expect(find.text('暂无本地记录'), findsNothing);
    expect(find.textContaining('2E015'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.pumpAndSettle();
    expect(find.textContaining('2E015'), findsOneWidget);
  });

  testWidgets('unreachable campus service suggests campus network',
      (tester) async {
    final client = _UnreachableBookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
        schoolClock: schoolMorning,
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BookingVenue.library.label));
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
        schoolClock: schoolMorning,
        useWebVpn: true,
        onWebVpnSessionRequired: () async {
          recoveries++;
          client.gatewayLoginRequired = false;
          return true;
        },
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    expect(recoveries, 1);
    expect(find.text('选择分区'), findsOneWidget);
  });

  testWidgets('view-only seats return to venue selection', (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.tap(find.text('仅查看座位情况'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(client.areaListCalls, 0);
    await tester.tap(find.byKey(const ValueKey('view-library')));
    await tester.tap(find.byKey(const ValueKey('view-scienceArt')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(client.areaListCalls, 2);
    expect(client.detailAreaCalls, 0);
    expect(find.byTooltip('我的预约'), findsNothing);
    expect(find.textContaining('开放座位数 9'), findsAtLeastNWidgets(1));
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看座位'));
    await tester.pumpAndSettle();
    expect(find.text('2E015'), findsOneWidget);
    expect(find.text('2E016'), findsOneWidget);
    await tester.tap(find.text('仅看可选座位'));
    await tester.pumpAndSettle();
    expect(find.text('2E016'), findsNothing);
    expect(find.text('确认预约'), findsNothing);
    expect(find.text('退出查看'), findsNothing);
    for (var step = 0; step < 5; step++) {
      await tester.tap(find.byTooltip('返回上一步'));
      await tester.pumpAndSettle();
    }
    expect(find.text('选择场馆'), findsOneWidget);
  });

  testWidgets('forward and back steps slide in opposite directions',
      (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pump(const Duration(milliseconds: 50));
    final enteringArea = tester.getTopLeft(find.byType(Scaffold).last).dx;
    expect(enteringArea, greaterThan(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回上一步'));
    await tester.pump(const Duration(milliseconds: 50));
    final enteringVenue = tester.getTopLeft(find.byType(Scaffold).last).dx;
    expect(enteringVenue, lessThan(0));
    await tester.pumpAndSettle();
    expect(find.text('选择场馆'), findsOneWidget);
  });

  testWidgets('rules and 24H help open local content and zoomable map',
      (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.pumpAndSettle();
    final rulesText = tester.widget<Text>(find.text('使用规则'));
    expect(rulesText.style?.fontSize, 14.5);
    expect(rulesText.style?.fontWeight, FontWeight.w400);
    expect(find.ancestor(of: find.text('使用规则'), matching: find.byType(InkWell)),
        findsNothing);
    await tester.tap(find.text('使用规则'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBookingInfoPage), findsOneWidget);
    expect(find.text('注意事项'), findsOneWidget);
    expect(find.textContaining('刷卡或人脸识别'), findsOneWidget);
    final paragraph = tester.widget<SelectableText>(find
        .ancestor(
          of: find.textContaining('刷卡或人脸识别'),
          matching: find.byType(SelectableText),
        )
        .first);
    expect(paragraph.style?.fontSize, 15.5);
    expect(paragraph.textSpan!.toPlainText(), contains('若未按时签到将被记录为违约行为'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text(BookingVenue.studySpace.label));
    await tester.pumpAndSettle();
    expect(find.text('座位分布'), findsOneWidget);
    expect(find.text('常见问题'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
    expect(tester.widget<Text>(find.text('座位分布')).style?.fontSize,
        rulesText.style?.fontSize);
    expect(tester.widget<Text>(find.text('常见问题')).style?.fontSize,
        rulesText.style?.fontSize);
    expect(
        find.ancestor(
          of: find.text('座位分布'),
          matching: find.byType(InkWell),
        ),
        findsNothing);
    await tester.tap(find.text('座位分布'));
    await tester.pumpAndSettle();
    final viewer =
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
    expect(viewer.maxScale, greaterThan(1));
    final image = tester.widget<Image>(find.byType(Image).first);
    expect((image.image as AssetImage).assetName, librarySeatsAsset);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);

    await tester.tap(find.text('常见问题'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBookingInfoPage), findsOneWidget);
    expect(find.text('区域分布（包括饮食、仓库、水房等）'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('无法预约/签到失败等'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    final qaParagraph = tester.widget<SelectableText>(find
        .ancestor(
          of: find.textContaining('无法预约/签到失败等'),
          matching: find.byType(SelectableText),
        )
        .first);
    expect(qaParagraph.style?.fontSize, 15.5);
    expect(qaParagraph.textSpan!.toPlainText(), contains('脸部识别/个人信息等：'));
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('座位分布'), findsOneWidget);
    await tester.tap(find.text('座位分布'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('关闭图片'));
    await tester.pumpAndSettle();
  });

  testWidgets('24H help stays on title rows at narrow width', (tester) async {
    tester.view.physicalSize = const Size(260, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text(BookingVenue.studySpace.label));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('座位分布'), findsOneWidget);
    expect(find.text('常见问题'), findsOneWidget);
    await tester.tap(find.text('二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('座位分布'), findsOneWidget);
  });

  testWidgets('area availability wraps as a complete item on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(260, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    final first = find.text('开放座位数 9 / 使用中 3');
    final available = find.text('可用 6');
    expect(first, findsOneWidget);
    expect(available, findsOneWidget);
    expect(tester.getTopLeft(available).dy,
        greaterThan(tester.getTopLeft(first).dy));
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'only today and tomorrow appear, and time boxes keep a valid interval',
      (tester) async {
    final client = _ManyDaysClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    expect(find.textContaining('今天'), findsOneWidget);
    expect(find.textContaining('明天'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(find.byType(RangeSlider), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byKey(const ValueKey('start-hour')), findsOneWidget);
    expect(find.byKey(const ValueKey('start-minute')), findsOneWidget);
    expect(find.byKey(const ValueKey('end-hour')), findsOneWidget);
    expect(find.byKey(const ValueKey('end-minute')), findsOneWidget);
    expect(find.textContaining('最短'), findsNothing);
    await pickTime(tester, 'start-hour', '10', '00');
    expect(boxValue(tester, 'start-hour'), '10');
    expect(boxValue(tester, 'end-hour'), '10');
    expect(boxValue(tester, 'end-minute'), '30');
    await pickTime(tester, 'end-hour', '10', '00');
    expect(boxValue(tester, 'start-hour'), '09');
    expect(boxValue(tester, 'start-minute'), '30');
    await pickTime(tester, 'end-hour', '18', '00');
    expect(boxValue(tester, 'start-hour'), '10');
    expect(boxValue(tester, 'end-hour'), '18');
    await pickTime(tester, 'start-hour', '21', '30');
    expect(boxValue(tester, 'start-hour'), '21');
    expect(boxValue(tester, 'start-minute'), '30');
    expect(boxValue(tester, 'end-hour'), '22');
    await tester.tap(find.byTooltip('返回上一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('明天'));
    await tester.pumpAndSettle();
    expect(boxValue(tester, 'start-hour'), '12');
    expect(boxValue(tester, 'start-minute'), '30');
    expect(boxValue(tester, 'end-hour'), '15');
    expect(boxValue(tester, 'end-minute'), '30');
  });

  testWidgets('missing minimum uses the smallest selectable step',
      (tester) async {
    final client = _NoMinimumClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(find.textContaining('最短'), findsNothing);
    await pickTime(tester, 'start-hour', '10', '00');
    expect(boxValue(tester, 'start-hour'), '10');
    expect(boxValue(tester, 'end-hour'), '10');
    expect(boxValue(tester, 'end-minute'), '30');
  });

  testWidgets('today has no default after the final valid start',
      (tester) async {
    final day = DateTime.parse(ThereBookingClient.schoolDay());
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: () => DateTime.utc(day.year, day.month, day.day, 21, 46),
    )));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(find.text('今天已无可预约时段，请选择明天'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNull);
  });

  testWidgets('today starts at the next selectable time', (tester) async {
    final day = DateTime.parse(ThereBookingClient.schoolDay());
    final client = _BookingClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: () => DateTime.utc(day.year, day.month, day.day, 8, 7),
    )));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(boxValue(tester, 'start-hour'), '08');
    expect(boxValue(tester, 'start-minute'), '30');
    expect(boxValue(tester, 'end-hour'), '10');
    expect(boxValue(tester, 'end-minute'), '30');
  });

  testWidgets('time fields and wheels use the active dark theme',
      (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    final spec = ShuYoThemes.byId(ShuYoThemes.systemDarkId);
    await tester.pumpWidget(MaterialApp(
      theme: spec.themeData(),
      home: LibraryBookingPage(
        accountService: UnifiedAccountService(),
        client: client,
        schoolClock: schoolMorning,
      ),
    ));
    await tester.tap(find.text(BookingVenue.library.label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('校本部图书馆自修区 - 二楼东侧'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(monthDay()));
    await tester.pumpAndSettle();
    expect(find.text('校本部图书馆自修区 - 二楼东侧 · 最长 8 小时'), findsOneWidget);
    expect(find.text('已选 2 小时'), findsOneWidget);
    expect(tester.widget<Text>(find.text('已选 2 小时')).style?.color,
        spec.colors.textTertiary);
    expect(find.text('开始'), findsNothing);
    expect(find.text('结束'), findsNothing);
    final material = tester.widget<Material>(find
        .ancestor(
          of: find.byKey(const ValueKey('start-hour')),
          matching: find.byType(Material),
        )
        .first);
    expect(material.color, spec.colors.surface);
    final box = tester.widget<Container>(find
        .descendant(
          of: find.byKey(const ValueKey('start-hour')),
          matching: find.byType(Container),
        )
        .first);
    expect((box.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(10));
    final digit = tester.widget<Text>(find.descendant(
      of: find.byKey(const ValueKey('start-hour')),
      matching: find.byType(Text),
    ));
    expect(digit.style?.fontSize, 22);
    await tester.tap(find.byKey(const ValueKey('start-hour')));
    await tester.pumpAndSettle();
    expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
        spec.colors.surface);
    expect(find.byType(CupertinoPicker), findsNWidgets(2));
    for (final picker
        in tester.widgetList<CupertinoPicker>(find.byType(CupertinoPicker))) {
      expect(picker.backgroundColor, spec.colors.surface);
      expect(picker.selectionOverlay, isNull);
    }
    final hourWheel = tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('time-wheel-小时')));
    final children =
        (hourWheel.childDelegate as ListWheelChildListDelegate).children;
    final selected =
        (children[hourWheel.scrollController!.selectedItem] as Center).child
            as Text;
    expect(selected.style?.color, spec.colors.accent);
    expect(selected.style?.fontWeight, FontWeight.w600);
    final adjacent = (children[1] as Center).child as Text;
    expect(adjacent.style?.fontWeight, FontWeight.w400);
    hourWheel.scrollController!.jumpToItem(2);
    await tester.pumpAndSettle();
    final movedWheel = tester
        .widget<CupertinoPicker>(find.byKey(const ValueKey('time-wheel-小时')));
    final movedChildren =
        (movedWheel.childDelegate as ListWheelChildListDelegate).children;
    final movedSelected = (movedChildren[2] as Center).child as Text;
    final previousSelected = (movedChildren[0] as Center).child as Text;
    expect(movedSelected.style?.color, spec.colors.accent);
    expect(movedSelected.style?.fontWeight, FontWeight.w600);
    expect(previousSelected.style?.fontWeight, FontWeight.w400);
  });

  testWidgets('booking venue choices persist and limit queries',
      (tester) async {
    final client = _BookingClient();
    addTearDown(client.dispose);
    Widget page() => MaterialApp(
            home: LibraryBookingPage(
          accountService: UnifiedAccountService(),
          client: client,
          schoolClock: schoolMorning,
        ));
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的预约'));
    await tester.pumpAndSettle();
    final next = find.text('下一步');
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '下一步'))
            .onPressed,
        isNull);
    await tester.tap(find.byKey(const ValueKey('booking-studySpace')));
    await tester.pumpAndSettle();
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(client.selectedVenues.toSet(), {BookingVenue.studySpace});
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的预约'));
    await tester.pumpAndSettle();
    final selected = tester.widget<CheckboxListTile>(
        find.byKey(const ValueKey('booking-studySpace')));
    expect(selected.value, isTrue);
    expect(
        tester
            .widget<CheckboxListTile>(
                find.byKey(const ValueKey('booking-library')))
            .value,
        isFalse);
  });

  testWidgets('bookings filter future and early-finished records',
      (tester) async {
    final client = _HistoryClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
        home: LibraryBookingPage(
      accountService: UnifiedAccountService(),
      client: client,
      schoolClock: schoolMorning,
    )));
    await tester.tap(find.text('我的预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('booking-studySpace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('B-034'), findsOneWidget);
    expect(find.textContaining('A-001'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    final nextDay = DateTime.parse(ThereBookingClient.schoolDay())
        .add(const Duration(days: 1));
    final day = '${nextDay.year}-${nextDay.month.toString().padLeft(2, '0')}-'
        '${nextDay.day.toString().padLeft(2, '0')}';
    expect(find.textContaining('$day 08:30'), findsNothing);
    expect(find.textContaining('${day.substring(5)} 08:30'), findsOneWidget);
    await tester.tap(find.text('待履约').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('B-034'), findsOneWidget);
    expect(find.textContaining('A-001'), findsNothing);
    await tester.tap(find.textContaining('B-034'));
    await tester.pumpAndSettle();
    expect(client.selectedVenues.last, BookingVenue.studySpace);
    expect(find.text('开始时间'), findsOneWidget);
    expect(find.text('结束时间'), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.text('已结束'));
    await tester.pumpAndSettle();
    expect(find.textContaining('A-001'), findsOneWidget);
    expect(find.textContaining('B-034'), findsNothing);
    expect(find.text('已提前结束'), findsOneWidget);
    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('B-034'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(client.cancelled, isTrue);
  });
}
