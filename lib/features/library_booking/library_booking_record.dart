import '../../data/services/there_booking_client.dart';

/// Presentation rules shared by the home and history booking lists.
final class LibraryBookingRecord {
  const LibraryBookingRecord._();

  static String venueName(Map<String, dynamic> item) =>
      BookingVenue.values
          .where((venue) => venue.roomType == item['roomType'])
          .firstOrNull
          ?.label ??
      '图书馆预约';

  static String category(Map<String, dynamic> item, DateTime schoolNow) {
    final status =
        (ThereBookingClient.string(item['status']) ?? '').toUpperCase();
    final label = ThereBookingClient.string(item['statusLabel']) ?? '';
    if (finishedEarly(item)) return '已结束';
    if (status == 'CANCEL' || label.contains('取消')) return '已取消';
    if (status == 'CX_7') return '已结束';
    if (status.startsWith('CX_') && status != 'CX_0') {
      return label.isEmpty ? '状态待确认' : label;
    }
    final now = DateTime.utc(
      schoolNow.year,
      schoolNow.month,
      schoolNow.day,
      schoolNow.hour,
      schoolNow.minute,
      schoolNow.second,
      schoolNow.millisecond,
      schoolNow.microsecond,
    );
    DateTime? parse(Object? value) {
      final text = ThereBookingClient.string(value);
      return text == null
          ? null
          : DateTime.tryParse('${text.replaceFirst(' ', 'T')}Z');
    }

    final begin = parse(item['beginTime']);
    final end = parse(item['endTime']);
    if (begin != null && now.isBefore(begin)) return '待履约';
    if (end != null && now.isBefore(end)) return '进行中';
    return '已结束';
  }

  static bool finishedEarly(Map<String, dynamic> item) {
    final original = ThereBookingClient.string(item['origEndAt']);
    final end = ThereBookingClient.string(item['endTime']);
    return original != null &&
        end != null &&
        end.compareTo(original) < 0 &&
        item['duration'] == 0;
  }

  static String displayTime(Object? value, DateTime schoolNow) {
    final text = ThereBookingClient.string(value);
    if (text == null || text.length < 16) return text ?? '待确认';
    final year = int.tryParse(text.substring(0, 4));
    return year == schoolNow.year
        ? text.substring(5, 16)
        : text.substring(0, 16);
  }
}
