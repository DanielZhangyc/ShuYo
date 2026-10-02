import 'package:shared_preferences/shared_preferences.dart';

class AcademicProgressDisplaySettingsService {
  AcademicProgressDisplaySettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const showGpaKey = 'academic.progress.display.showGpa';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<bool> loadShowGpa() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(showGpaKey) ?? false;
  }

  Future<void> saveShowGpa(bool showGpa) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(showGpaKey, showGpa);
  }
}
