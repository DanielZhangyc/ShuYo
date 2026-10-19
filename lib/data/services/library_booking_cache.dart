import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Account-scoped local history of server-confirmed bookings.
class LibraryBookingCache {
  LibraryBookingCache({Future<SharedPreferences> Function()? preferencesLoader})
      : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;

  String _key(String studentId) =>
      'library_booking.recent.v1.${Uri.encodeComponent(studentId)}';

  String? _bookingId(Object? value) {
    if (value is! String && value is! num) return null;
    final id = value.toString().trim();
    return id.isEmpty ? null : id;
  }

  Future<List<Map<String, dynamic>>> load(String studentId) async {
    try {
      final raw = (await _preferencesLoader()).getString(_key(studentId));
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final records = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final record =
            item.map((key, value) => MapEntry(key.toString(), value));
        final id = _bookingId(record['id']);
        if (id != null) records.add({...record, 'id': id});
      }
      return records;
    } on Object {
      return [];
    }
  }

  Future<void> replaceVenue(String studentId, String roomType,
      List<Map<String, dynamic>> recent) async {
    final existing = await load(studentId);
    final byId = <String, Map<String, dynamic>>{};
    for (final item in existing) {
      final id = _bookingId(item['id']);
      if (id != null && item['roomType'] != roomType) {
        byId[id] = {...item, 'id': id};
      }
    }
    for (final item in recent) {
      if (item['roomType'] != roomType) continue;
      final id = _bookingId(item['id']);
      if (id == null) continue;
      byId[id] = _storedRecord(item, id);
    }
    final records = byId.values.toList()
      ..sort((a, b) => (b['beginTime']?.toString() ?? '')
          .compareTo(a['beginTime']?.toString() ?? ''));
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(_key(studentId), jsonEncode(records));
    } on Object {
      // Local storage is advisory; a successful server read remains usable.
    }
  }

  /// Adds or updates records without dropping older history for this venue.
  Future<void> mergeVenue(String studentId, String roomType,
      List<Map<String, dynamic>> recent) async {
    final byId = <String, Map<String, dynamic>>{};
    for (final item in await load(studentId)) {
      final id = _bookingId(item['id']);
      if (id != null) byId[id] = {...item, 'id': id};
    }
    for (final item in recent) {
      if (item['roomType'] != roomType) continue;
      final id = _bookingId(item['id']);
      if (id == null) continue;
      byId[id] = _storedRecord(item, id);
    }
    final records = byId.values.toList()
      ..sort((a, b) => (b['beginTime']?.toString() ?? '')
          .compareTo(a['beginTime']?.toString() ?? ''));
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(_key(studentId), jsonEncode(records));
    } on Object {
      // Local storage is advisory; a successful server read remains usable.
    }
  }

  Map<String, dynamic> _storedRecord(Map<String, dynamic> item, String id) => {
        for (final key in [
          'roomType',
          'roomName',
          'officeAreaName',
          'allOfficeAreaName',
          'beginTime',
          'endTime',
          'createdAt',
          'checkInAt',
          'status',
          'statusLabel',
          'origEndAt',
          'duration',
        ])
          if (item[key] is String || item[key] is num) key: item[key],
        'id': id,
        if (item['cxCurrent'] is bool) 'cxCurrent': item['cxCurrent'],
        if (item['abilities'] is List)
          'abilities': (item['abilities'] as List)
              .whereType<String>()
              .where((value) =>
                  value == 'cancel' || value == 'sign' || value == 'close')
              .toList(),
      };

  Future<void> removeBooking(String studentId, String bookingId) async {
    final records = await load(studentId);
    records.removeWhere((item) => _bookingId(item['id']) == bookingId);
    try {
      final prefs = await _preferencesLoader();
      await prefs.setString(_key(studentId), jsonEncode(records));
    } on Object {
      // Avoid showing stale status in memory even when persistence fails.
    }
  }
}
