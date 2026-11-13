import 'package:shared_preferences/shared_preferences.dart';

import '../models/classroom.dart';

class AcademicProfilePreferences {
  AcademicProfilePreferences({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const preferredCampusKey = 'client.profile.preferred_campus';
  static const nicknameKeyPrefix = 'client.profile.nickname.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<String?> loadNickname(String studentId) async {
    final id = studentId.trim();
    if (id.isEmpty) return null;
    final value = (await _preferencesLoader())
        .getString('$nicknameKeyPrefix${Uri.encodeComponent(id)}')
        ?.trim();
    return value == null || value.isEmpty || value == id ? null : value;
  }

  Future<void> saveNickname(String studentId, String? nickname) async {
    final id = studentId.trim();
    if (id.isEmpty) throw ArgumentError.value(studentId, 'studentId');
    final value = nickname?.trim() ?? '';
    final prefs = await _preferencesLoader();
    final key = '$nicknameKeyPrefix${Uri.encodeComponent(id)}';
    if (value.isEmpty || value == id) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<String> loadPreferredCampus() async {
    final value = (await _preferencesLoader()).getString(preferredCampusKey);
    return ClassroomCampus.knownNames.contains(value)
        ? value!
        : ClassroomCampus.defaultName;
  }

  Future<void> savePreferredCampus(String campus) async {
    if (!ClassroomCampus.knownNames.contains(campus)) {
      throw ArgumentError.value(campus, 'campus');
    }
    await (await _preferencesLoader()).setString(preferredCampusKey, campus);
  }
}
