import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/library_booking_cache.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('keeps confirmed recent records by account and venue', () async {
    final cache = LibraryBookingCache();
    await cache.replaceVenue('student-a', 'LIB_SEAT', [
      {
        'id': 'LIB_1',
        'roomType': 'LIB_SEAT',
        'roomName': '2E015',
        'beginTime': '2026-10-04 08:30:00',
        'endTime': '2026-10-04 09:30:00',
        'ownerMobile': 'not-for-cache',
      },
    ]);
    await cache.replaceVenue('student-a', 'STATION', [
      {
        'id': 'STATION_1',
        'roomType': 'STATION',
        'roomName': 'B-034',
        'beginTime': '2026-10-05 08:30:00',
        'endTime': '2026-10-05 09:30:00',
      },
    ]);
    final records = await cache.load('student-a');
    expect(records.map((item) => item['id']), ['STATION_1', 'LIB_1']);
    expect(records.first.containsKey('ownerMobile'), isFalse);
    expect(await cache.load('student-b'), isEmpty);

    await cache.removeBooking('student-a', 'LIB_1');
    expect((await cache.load('student-a')).map((item) => item['id']),
        ['STATION_1']);
  });

  test('a damaged local snapshot reads as empty', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('library_booking.recent.v1.student-a', '{broken');
    expect(await LibraryBookingCache().load('student-a'), isEmpty);
  });
}
