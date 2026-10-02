import '../models/academic_schedule.dart';
import '../models/academic_progress.dart';
import '../models/announcement.dart';
import '../models/classroom.dart';
import '../models/course_rating.dart';
import '../repositories/academic_schedule_repository.dart';
import '../repositories/academic_progress_repository.dart';
import '../repositories/announcement_repository.dart';
import '../repositories/classroom_repository.dart';
import '../repositories/course_rating_repository.dart';

class DemoAcademicScheduleRepository extends AcademicScheduleRepository {
  DemoAcademicScheduleRepository(this.schedule);

  final AcademicSchedule schedule;

  @override
  Future<AcademicSchedule?> loadCachedSchedule() async => schedule;

  @override
  Future<AcademicSchedule> refreshSchedule() async => schedule;

  @override
  Future<void> saveCachedSchedule(AcademicSchedule schedule) async {}
}

class DemoAcademicProgressRepository extends AcademicProgressRepository {
  DemoAcademicProgressRepository()
      : progress = AcademicProgress(
          studentId: 'DEMO0001',
          gpa: '3.65',
          plannedCourses: 40,
          passedCourses: 16,
          ongoingCourses: 5,
          notTakenCourses: 19,
          fetchedAt: DateTime(2026, 9, 1),
          nodes: const [
            AcademicProgressNode(
              id: 'demo-main',
              parentId: '',
              name: '主修',
              requiredCredits: 160,
              earnedCredits: 62,
              passed: false,
              courseKind: '',
              isLeaf: false,
            ),
            AcademicProgressNode(
              id: 'demo-basic',
              parentId: 'demo-main',
              name: '公共基础课程',
              requiredCredits: 72,
              earnedCredits: 36,
              passed: false,
              courseKind: '1',
              isLeaf: true,
              courses: [
                AcademicProgressCourse(
                  id: 'DEMO101',
                  code: 'DEMO101',
                  name: '大学英语',
                  status: '4',
                  credits: '2.0',
                  grade: '88',
                  gradePoint: '3.7',
                  academicYear: '2025-2026',
                  term: '秋',
                  suggestedYear: '2025-2026',
                  suggestedTerm: '秋',
                  nature: '公共基础课',
                  category: '',
                  hours: '理论(2.0)',
                ),
                AcademicProgressCourse(
                  id: 'DEMO102',
                  code: 'DEMO102',
                  name: '计算思维',
                  status: '1',
                  credits: '3.0',
                  grade: '',
                  gradePoint: '',
                  academicYear: '2026-2027',
                  term: '秋',
                  suggestedYear: '2026-2027',
                  suggestedTerm: '秋',
                  nature: '公共基础课',
                  category: '',
                  hours: '理论(2.0)-上机(1.0)',
                ),
                AcademicProgressCourse(
                  id: 'DEMO103',
                  code: 'DEMO103',
                  name: '程序设计基础',
                  status: '3',
                  credits: '3.0',
                  grade: '',
                  gradePoint: '',
                  academicYear: '',
                  term: '',
                  suggestedYear: '2027-2028',
                  suggestedTerm: '秋',
                  nature: '公共基础课',
                  category: '',
                  hours: '理论(2.0)-上机(1.0)',
                ),
              ],
            ),
            AcademicProgressNode(
              id: 'zgzsxx',
              parentId: '',
              name: '资格证书信息',
              requiredCredits: null,
              earnedCredits: null,
              passed: null,
              courseKind: 'certificate',
              isLeaf: true,
            ),
          ],
        );

  final AcademicProgress progress;

  @override
  Future<AcademicProgress?> loadCachedProgress() async => progress;

  @override
  Future<AcademicProgress> refreshProgress() async => progress;
}

class DemoAnnouncementRepository extends AnnouncementRepository {
  DemoAnnouncementRepository({
    required this.items,
    required this.details,
  });

  final List<AnnouncementListItem> items;
  final Map<String, AnnouncementDetail> details;

  @override
  Future<List<AnnouncementListItem>> loadCachedAnnouncements() async => items;

  @override
  Future<List<AnnouncementListItem>> fetchAnnouncements(
          {bool forceRefresh = false}) async =>
      items;

  @override
  Future<AnnouncementDetail> fetchDetail(AnnouncementListItem item) async =>
      details[item.title] ??
      AnnouncementDetail(title: item.title, url: item.url, blocks: const []);

  @override
  Future<AnnouncementHomeSummary> homeSummary() async => items.isEmpty
      ? const AnnouncementHomeSummary('点击查看通知公告')
      : AnnouncementHomeSummary(items.first.title);
}

class DemoClassroomRepository extends ClassroomRepository {
  DemoClassroomRepository({
    required this.options,
    required this.schedule,
  });

  final ClassroomSearchOptions options;
  final ClassroomBuildingSchedule schedule;

  @override
  Future<ClassroomSearchOptions> loadOptions(
          {bool forceRefresh = false}) async =>
      options;

  @override
  Future<ClassroomAvailabilityResult> search(ClassroomAvailabilityQuery query,
      {bool forceRefresh = false}) async {
    final supported = query.building.id == schedule.building.id &&
        query.date.year == 2026 &&
        query.date.month == 9 &&
        query.date.day == 1;
    if (!supported) {
      return ClassroomAvailabilityResult(
        building: query.building,
        date: query.date,
        startSection: query.startSection,
        endSection: query.endSection,
        floors: const [],
      );
    }
    final floors = schedule.floors.map((floor) {
      final available = floor.rooms
          .where((room) => room.isFreeFor(query.startSection, query.endSection))
          .toList(growable: false);
      return ClassroomFloorAvailability(
          floor: floor, rooms: floor.rooms, availableRooms: available);
    }).toList(growable: false);
    return ClassroomAvailabilityResult(
        building: query.building,
        date: query.date,
        startSection: query.startSection,
        endSection: query.endSection,
        floors: floors);
  }
}

class DemoCourseRatingRepository extends CourseRatingRepository {
  DemoCourseRatingRepository(this.latest);

  final CourseRatingLatestResult latest;

  @override
  Future<CourseRatingLatestResult> fetchLatest(
          {bool forceRefresh = false}) async =>
      latest;

  @override
  Future<CourseRatingSearchResult> search(String keyword,
      {bool forceRefresh = false}) async {
    final query = normalizeKeyword(keyword).toLowerCase();
    if (query.isEmpty) {
      return const CourseRatingSearchResult(
          query: '', courses: [], teachers: []);
    }
    final courses = <CourseRatingCourse>[];
    final teachers = <CourseRatingTeacher>[];
    for (final item in latest.ratings) {
      if (item.courseName.toLowerCase().contains(query) ||
          item.courseCode.toLowerCase().contains(query)) {
        courses.add(CourseRatingCourse(
            id: item.courseId,
            name: item.courseName,
            courseCode: item.courseCode));
      }
      if (item.teacherName.toLowerCase().contains(query)) {
        teachers.add(
            CourseRatingTeacher(id: item.teacherId, name: item.teacherName));
      }
    }
    return CourseRatingSearchResult(
        query: keyword,
        courses: _uniqueCourses(courses),
        teachers: _uniqueTeachers(teachers));
  }

  @override
  Future<CourseRatingCourseTeachers> fetchCourseTeachers(
      CourseRatingCourse course,
      {bool forceRefresh = false}) async {
    final teachers = latest.ratings
        .where((item) => item.courseName == course.name)
        .map((item) =>
            CourseRatingTeacher(id: item.teacherId, name: item.teacherName))
        .toList();
    return CourseRatingCourseTeachers(
        course: course, teachers: _uniqueTeachers(teachers));
  }

  @override
  Future<CourseRatingTeacherCourses> fetchTeacherCourses(
      CourseRatingTeacher teacher,
      {bool forceRefresh = false}) async {
    final courses = latest.ratings
        .where((item) => item.teacherName == teacher.name)
        .map((item) => CourseRatingCourse(
            id: item.courseId,
            name: item.courseName,
            courseCode: item.courseCode))
        .toList();
    return CourseRatingTeacherCourses(
        teacher: teacher, courses: _uniqueCourses(courses));
  }

  @override
  Future<CourseRatingDetail> fetchRatingDetail(
      {required CourseRatingCourse course,
      required CourseRatingTeacher teacher,
      int page = 1,
      bool forceRefresh = false}) async {
    final ratings = latest.ratings
        .where((item) =>
            item.courseName == course.name && item.teacherName == teacher.name)
        .map((item) => CourseRatingItem(
            id: item.id,
            score: item.score,
            content: item.content,
            createdAt: item.createdAt,
            upvotes: item.upvotes,
            user: item.user))
        .toList(growable: false);
    final average = ratings.isEmpty
        ? 0.0
        : ratings.map((item) => item.score).reduce((a, b) => a + b) /
            ratings.length;
    return CourseRatingDetail(
        course: course,
        teacher: teacher,
        average: average,
        total: ratings.length,
        page: page,
        perPage: ratings.length,
        ratings: ratings,
        radar: const CourseRatingRadar(categories: [], values: []));
  }

  static List<CourseRatingCourse> _uniqueCourses(
      List<CourseRatingCourse> values) {
    final map = <String, CourseRatingCourse>{};
    for (final value in values) {
      map[value.name] = value;
    }
    return map.values.toList(growable: false);
  }

  static List<CourseRatingTeacher> _uniqueTeachers(
      List<CourseRatingTeacher> values) {
    final map = <int, CourseRatingTeacher>{};
    for (final value in values) {
      map[value.id] = value;
    }
    return map.values.toList(growable: false);
  }
}
