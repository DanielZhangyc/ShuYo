import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/academic_progress.dart';
import '../services/academic_account_store.dart';
import '../services/academic_progress_api_client.dart';

class AcademicProgressRepository {
  AcademicProgressRepository({
    AcademicProgressApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _apiClient = apiClient,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const cacheKey = 'academic.progress.cache';

  AcademicProgressApiClient? _apiClient;
  AcademicProgressApiClient get _client =>
      _apiClient ??= AcademicProgressApiClient();
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<AcademicProgress?> loadCachedProgress() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final progress = AcademicProgress.fromJson(decoded);
    final activeStudentId = await AcademicAccountStore(
      preferencesLoader: _preferencesLoader,
    ).loadDataStudentId();
    if (activeStudentId != null &&
        activeStudentId.isNotEmpty &&
        progress.studentId != activeStudentId) {
      return null;
    }
    return progress;
  }

  Future<AcademicProgress> refreshProgress() async {
    final progress = await _client.fetchProgress();
    final prefs = await _preferencesLoader();
    await prefs.setString(cacheKey, jsonEncode(progress.toJson()));
    return progress;
  }
}
