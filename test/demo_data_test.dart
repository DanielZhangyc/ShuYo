import 'package:flutter_test/flutter_test.dart';
import 'package:shuyo/data/demo/demo_data_bundle.dart';
import 'package:shuyo/data/demo/demo_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads bundled demo fixtures without personal identifiers', () async {
    final data = await DemoDataBundle.load();
    expect(data.schedule.term.studentName, '演示同学');
    expect(data.schedule.term.studentId, 'DEMO0001');
    expect(data.announcements, hasLength(4));
    expect(data.courseRatings.ratings, hasLength(20));
    expect(
      data.courseRatings.ratings.every(
        (rating) =>
            rating.teacherName.startsWith('教师') &&
            rating.user.username.startsWith('同学') &&
            !rating.content.contains('刘书朋') &&
            !rating.content.contains('王永') &&
            !rating.content.contains('渠老师'),
      ),
      isTrue,
    );
    expect(data.classroomSchedule.building.name, 'GA楼');
  });

  test('demo session credentials are exact', () {
    expect(DemoSession.matchesCredentials('admin2512', 'abc123456'), isTrue);
    expect(DemoSession.matchesCredentials('admin2512', 'wrong'), isFalse);
  });
}
