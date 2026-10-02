import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/academic_ranking.dart';
import '../services/academic_account_store.dart';
import '../services/academic_ranking_api_client.dart';

class AcademicRankingRepository {
  AcademicRankingRepository({
    AcademicRankingApiClient? apiClient,
    Future<SharedPreferences> Function()? preferencesLoader,
  })  : _apiClient = apiClient,
        _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const cacheKey = 'academic.ranking.cache';

  AcademicRankingApiClient? _apiClient;
  AcademicRankingApiClient get _client =>
      _apiClient ??= AcademicRankingApiClient();
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<AcademicRanking?> loadCachedRanking() async {
    final prefs = await _preferencesLoader();
    final raw = prefs.getString(cacheKey);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final ranking = AcademicRanking.fromJson(decoded);
    final activeStudentId = await AcademicAccountStore().loadStudentId();
    if (activeStudentId != null &&
        activeStudentId.isNotEmpty &&
        ranking.studentId != activeStudentId) {
      return null;
    }
    return ranking;
  }

  Future<AcademicRanking> refreshRanking() async {
    final studentId = await AcademicAccountStore().loadStudentId() ?? '';
    final ranking =
        await _client.fetchCurrentRanking(expectedStudentId: studentId);
    final prefs = await _preferencesLoader();
    await prefs.setString(cacheKey, jsonEncode(ranking.toJson()));
    return ranking;
  }
}
