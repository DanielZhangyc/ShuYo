import 'package:shared_preferences/shared_preferences.dart';

class AcademicProgressDisplaySettingsService {
  AcademicProgressDisplaySettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const showGpaKey = 'academic.progress.display.showGpa';
  static const showRankingKey = 'academic.progress.display.showRanking';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<bool> loadShowGpa() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(showGpaKey) ?? false;
  }

  Future<void> saveShowGpa(bool showGpa) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(showGpaKey, showGpa);
  }

  Future<bool> loadShowRanking() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(showRankingKey) ?? false;
  }

  Future<void> saveShowRanking(bool showRanking) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(showRankingKey, showRanking);
  }
}
