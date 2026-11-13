import '../models/academic_schedule.dart';

/// Day and section pairs free in every selected schedule for one teaching week.
Set<(int, int)> commonFreeSections(List<AcademicSchedule> schedules, int week,
    {int maxSection = 12}) {
  if (schedules.length < 2 ||
      schedules.any((schedule) => week < 1 || week > schedule.maxWeek)) {
    return const {};
  }
  final busy = <(int, int)>{};
  for (final schedule in schedules) {
    for (final item in schedule.sessionsForWeek(week)) {
      final sections = item.sections.isEmpty
          ? [for (var n = item.startSection; n <= item.endSection; n++) n]
          : item.sections;
      for (final section in sections) {
        if (item.weekday >= 1 &&
            item.weekday <= 7 &&
            section >= 1 &&
            section <= maxSection) {
          busy.add((item.weekday, section));
        }
      }
    }
  }
  return {
    for (var day = 1; day <= 7; day++)
      for (var section = 1; section <= maxSection; section++)
        if (!busy.contains((day, section))) (day, section),
  };
}
