import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AcademicScheduleDisplaySettings {
  const AcademicScheduleDisplaySettings({
    required this.colorful,
    required this.showTeacher,
    this.showCredit = false,
    this.showNonCurrentWeekCourses = true,
  });

  final bool colorful;
  final bool showTeacher;
  final bool showCredit;
  final bool showNonCurrentWeekCourses;

  AcademicScheduleDisplaySettings copyWith({
    bool? colorful,
    bool? showTeacher,
    bool? showCredit,
    bool? showNonCurrentWeekCourses,
  }) {
    return AcademicScheduleDisplaySettings(
      colorful: colorful ?? this.colorful,
      showTeacher: showTeacher ?? this.showTeacher,
      showCredit: showCredit ?? this.showCredit,
      showNonCurrentWeekCourses:
          showNonCurrentWeekCourses ?? this.showNonCurrentWeekCourses,
    );
  }
}

class AcademicScheduleDisplayState {
  const AcademicScheduleDisplayState({
    required this.settings,
    required this.courseColorValues,
  });

  final AcademicScheduleDisplaySettings settings;
  final Map<String, int> courseColorValues;
}

class AcademicScheduleDisplaySettingsService {
  AcademicScheduleDisplaySettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _colorfulKey = 'academic.schedule.display.colorful';
  static const _showTeacherKey = 'academic.schedule.display.showTeacher';
  static const _showCreditKey = 'academic.schedule.display.showCredit';
  static const _showNonCurrentWeekCoursesKey =
      'academic.schedule.display.showNonCurrentWeekCourses';
  static const _courseColorsKey = 'academic.schedule.display.courseColors';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<AcademicScheduleDisplayState> loadState() async {
    final prefs = await _preferencesLoader();
    return AcademicScheduleDisplayState(
      settings: _settingsFromPreferences(prefs),
      courseColorValues: _courseColorsFromPreferences(prefs),
    );
  }

  Future<AcademicScheduleDisplaySettings> loadSettings() async {
    final prefs = await _preferencesLoader();
    return _settingsFromPreferences(prefs);
  }

  AcademicScheduleDisplaySettings _settingsFromPreferences(
    SharedPreferences prefs,
  ) {
    return AcademicScheduleDisplaySettings(
      colorful: prefs.getBool(_colorfulKey) ?? true,
      showTeacher: prefs.getBool(_showTeacherKey) ?? false,
      showCredit: prefs.getBool(_showCreditKey) ?? false,
      showNonCurrentWeekCourses:
          prefs.getBool(_showNonCurrentWeekCoursesKey) ?? true,
    );
  }

  Future<AcademicScheduleDisplaySettings> saveSettings(
    AcademicScheduleDisplaySettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(_colorfulKey, settings.colorful);
    await prefs.setBool(_showTeacherKey, settings.showTeacher);
    await prefs.setBool(_showCreditKey, settings.showCredit);
    await prefs.setBool(
      _showNonCurrentWeekCoursesKey,
      settings.showNonCurrentWeekCourses,
    );
    return settings;
  }

  Future<Map<String, int>> loadCourseColors() async {
    final prefs = await _preferencesLoader();
    return _courseColorsFromPreferences(prefs);
  }

  Map<String, int> _courseColorsFromPreferences(SharedPreferences prefs) {
    final raw = prefs.getString(_courseColorsKey);
    if (raw == null || raw.isEmpty) {
      return <String, int>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return <String, int>{};
      }
      return <String, int>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is int)
            entry.key as String: entry.value as int,
      };
    } on Object {
      return <String, int>{};
    }
  }

  Future<void> saveCourseColor(String key, int colorValue) async {
    final colors = await loadCourseColors();
    colors[key] = colorValue;
    final prefs = await _preferencesLoader();
    await prefs.setString(_courseColorsKey, jsonEncode(colors));
  }
}
