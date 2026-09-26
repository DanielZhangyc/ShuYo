import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/models/academic_schedule.dart';
import 'package:shuyo/data/repositories/academic_schedule_repository.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/academic_schedule_api_client.dart';
import 'package:shuyo/data/services/academic_schedule_display_settings_service.dart';
import 'package:shuyo/data/services/academic_schedule_notification_service.dart';
import 'package:shuyo/data/services/academic_schedule_widget_service.dart';
import 'package:shuyo/features/home/academic_schedule_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'shows non-current-week courses unless a current course occupies the slot',
      (tester) async {
    final restoreFlutterError = _ignoreListTileBackgroundWarning();
    addTearDown(restoreFlutterError);
    final repository = AcademicScheduleRepository(
      apiClient: AcademicScheduleApiClient(
        authService: _FakeAcademicAuthService(),
      ),
    );
    final state = AcademicScheduleCacheState(
      schedule: _schedule,
      weekState: ScheduleWeekState(
        currentWeek: 1,
        anchorMonday: AcademicScheduleRepository.startOfWeek(DateTime.now()),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AcademicSchedulePage(
          repository: repository,
          notificationService:
              AcademicScheduleNotificationService(repository: repository),
          widgetService: AcademicScheduleWidgetService(repository: repository),
          onLoginRequired: () async {},
          initialState: state,
          initialDisplayState: const AcademicScheduleDisplayState(
            settings: AcademicScheduleDisplaySettings(
              colorful: true,
              showTeacher: false,
            ),
            courseColorValues: {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('本周课程'), findsOneWidget);
    expect(find.text('下周课程'), findsOneWidget);
    expect(find.text('被本周课程覆盖'), findsNothing);
    final nonCurrentBlock = find.byKey(
      const ValueKey('schedule-course-next'),
    );
    expect(nonCurrentBlock, findsOneWidget);
    final nonCurrentMaterial = tester.widget<Material>(
      find.descendant(of: nonCurrentBlock, matching: find.byType(Material)),
    );
    expect(
      nonCurrentMaterial.color,
      const Color(0xFFBDBDBD),
    );

    await tester.tap(find.text('下周课程'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示设置'));
    await tester.pumpAndSettle();
    expect(find.text('显示非本周课程'), findsOneWidget);
    await tester.tap(find.text('显示非本周课程'));
    await tester.ensureVisible(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('本周课程'), findsOneWidget);
    expect(find.text('下周课程'), findsNothing);
  });

  testWidgets('shows credit directly below course metadata in display order',
      (tester) async {
    final restoreFlutterError = _ignoreListTileBackgroundWarning();
    addTearDown(restoreFlutterError);
    final repository = AcademicScheduleRepository(
      apiClient: AcademicScheduleApiClient(
        authService: _FakeAcademicAuthService(),
      ),
    );
    final state = AcademicScheduleCacheState(
      schedule: _schedule,
      weekState: ScheduleWeekState(
        currentWeek: 1,
        anchorMonday: AcademicScheduleRepository.startOfWeek(DateTime.now()),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AcademicSchedulePage(
          repository: repository,
          notificationService:
              AcademicScheduleNotificationService(repository: repository),
          widgetService: AcademicScheduleWidgetService(repository: repository),
          onLoginRequired: () async {},
          initialState: state,
          initialDisplayState: const AcademicScheduleDisplayState(
            settings: AcademicScheduleDisplaySettings(
              colorful: false,
              showTeacher: false,
              showCredit: true,
            ),
            courseColorValues: {},
          ),
        ),
      ),
    );
    await tester.pump();

    final currentCourseBlock = find.byKey(
      const ValueKey('schedule-course-current'),
    );
    final creditText = find.descendant(
      of: currentCourseBlock,
      matching: find.text('2'),
    );
    expect(creditText, findsOneWidget);
    expect(find.text('张老师'), findsNothing);
    expect(
      tester.getTopLeft(creditText).dy,
      greaterThan(tester.getTopLeft(find.text('本周课程')).dy),
    );

    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示设置'));
    await tester.pumpAndSettle();
    expect(find.text('显示学分'), findsOneWidget);
    await tester.tap(find.text('显示教师'));
    await tester.ensureVisible(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    expect(find.text('张老师'), findsOneWidget);
    expect(creditText, findsOneWidget);
    expect(
      tester.getTopLeft(creditText).dy,
      greaterThan(tester.getTopLeft(find.text('张老师')).dy),
    );
  });
}

void Function() _ignoreListTileBackgroundWarning() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().startsWith(
          'ListTile background color or ink splashes may be invisible.',
        )) {
      return;
    }
    previous?.call(details);
  };
  return () => FlutterError.onError = previous;
}

class _FakeAcademicAuthService implements AcademicAuthService {
  @override
  Future<void> clearAccount() async {}

  @override
  Future<Set<String>> clearCookies() async => {};

  @override
  Future<void> markLoggedIn() async {}

  @override
  Future<String?> cookieHeader({Uri? targetUri}) async => null;

  @override
  Future<bool> hasWebVpnSession() async => false;

  @override
  Future<bool> hasAcademicSession() async => false;

  @override
  Future<WebVpnSessionStatus> validateDirectAcademicSession() async =>
      WebVpnSessionStatus.loginRequired;

  @override
  Future<WebVpnSessionStatus> validateWebVpnSession() async =>
      WebVpnSessionStatus.loginRequired;
}

CourseSession _session({
  required String id,
  required String name,
  required int weekday,
  required List<int> weeks,
  String teacherName = '',
  String credit = '',
}) {
  return CourseSession(
    id: id,
    courseName: name,
    courseCode: id,
    teacherName: teacherName,
    campus: '',
    location: '',
    weekday: weekday,
    startSection: 1,
    endSection: 2,
    sections: const [1, 2],
    weeks: weeks,
    weekText: weeks.join(','),
    credit: credit,
    note: '',
  );
}

final _schedule = AcademicSchedule(
  term: const AcademicTerm(
    yearCode: '2026',
    termCode: '3',
    academicYearName: '2026-2027',
    termName: '秋',
    studentName: '',
    studentId: '',
    className: '',
  ),
  sessions: [
    _session(
      id: 'current',
      name: '本周课程',
      weekday: 1,
      weeks: const [1],
      teacherName: '张老师',
      credit: '2',
    ),
    _session(id: 'covered', name: '被本周课程覆盖', weekday: 1, weeks: const [2]),
    _session(id: 'next', name: '下周课程', weekday: 2, weeks: const [2]),
  ],
  untimedCourses: const [],
  fetchedAt: DateTime(2026, 8, 31),
);
