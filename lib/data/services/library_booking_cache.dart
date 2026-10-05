import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A small, account-scoped snapshot of server-confirmed recent bookings.
class LibraryBookingCache {
  LibraryBookingCache({Future<SharedPreferences> Function()? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  String _key(String studentId) =>
      'library_booking.recent.v1.${Uri.encodeComponent(studentId)}';

  Future<List<Map<String, dynamic>>> load(String studentId) async {
    try {
      final raw = (await _preferencesLoader()).getString(_key(studentId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final item in decoded)
          if (item is Map)
            item.map((key, value) => MapEntry(key.toString(), value)),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> replaceVenue(String studentId, String roomType,
      List<Map<String, dynamic>> recent) async {
    final existing = await load(studentId);
    final byId = <String, Map<String, dynamic>>{};
    for (final item in existing) {
      final id = item['id'];
      if (id is String && item['roomType'] != roomType) byId[id] = item;
    }
    for (final item in recent) {
      if (item['roomType'] != roomType) continue;
      final id = item['id'];
      if (id is! String || id.isEmpty) continue;
      byId[id] = {
        for (final key in [
          'id',
          'roomType',
          'roomName',
          'officeAreaName',
          'allOfficeAreaName',
          'beginTime',
          'endTime',
          'status',
          'statusLabel',
          'origEndAt',
          'duration',
        ])
          if (item[key] is String || item[key] is num) key: item[key],
      };
    }
    final records = byId.values.toList()
      ..sort((a, b) => (b['beginTime']?.toString() ?? '')
          .compareTo(a['beginTime']?.toString() ?? ''));
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(
          _key(studentId), jsonEncode(records.take(30).toList()));
    } on Object {
      // Local storage is advisory; a successful server read remains usable.
    }
  }

  Future<void> removeBooking(String studentId, String bookingId) async {
    final records = await load(studentId);
    records.removeWhere((item) => item['id'] == bookingId);
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(_key(studentId), jsonEncode(records));
    } on Object {
      // Avoid showing stale status in memory even when persistence fails.
    }
  }
}
