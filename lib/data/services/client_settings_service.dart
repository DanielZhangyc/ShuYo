import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_tab.dart';

class ClientNotificationSettings {
  const ClientNotificationSettings({
    required this.scheduleEnabled,
  });

  final bool scheduleEnabled;

  ClientNotificationSettings copyWith({
    bool? scheduleEnabled,
  }) {
    return ClientNotificationSettings(
      scheduleEnabled: scheduleEnabled ?? this.scheduleEnabled,
    );
  }
}

class ClientNetworkSettings {
  const ClientNetworkSettings({
    required this.webVpnEnabled,
  });

  final bool webVpnEnabled;

  ClientNetworkSettings copyWith({
    bool? webVpnEnabled,
  }) {
    return ClientNetworkSettings(
      webVpnEnabled: webVpnEnabled ?? this.webVpnEnabled,
    );
  }
}

class ClientSettingsService {
  ClientSettingsService({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const scheduleNotificationsEnabledKey =
      'client.notifications.schedule.enabled';
  static const webVpnEnabledKey = 'client.network.webvpn.enabled';
  static const startupOnboardingCompletedKey =
      'client.onboarding.startup.completed';
  static const themeIdKey = 'client.theme.id';
  static const followSystemThemeKey = 'client.theme.follow_system';
  static const startupTabKey = 'client.startup.tab';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<ClientNotificationSettings> loadNotificationSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNotificationSettings(
      // Course reminders are opt-in. Permission prompts should only happen
      // after the user explicitly enables reminders in settings.
      scheduleEnabled: prefs.getBool(scheduleNotificationsEnabledKey) ?? false,
    );
  }

  Future<ClientNotificationSettings> saveNotificationSettings(
    ClientNotificationSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(
      scheduleNotificationsEnabledKey,
      settings.scheduleEnabled,
    );
    return settings;
  }

  Future<ClientNetworkSettings> loadNetworkSettings() async {
    final prefs = await _preferencesLoader();
    return ClientNetworkSettings(
      webVpnEnabled: prefs.getBool(webVpnEnabledKey) ?? false,
    );
  }

  Future<ClientNetworkSettings> saveNetworkSettings(
    ClientNetworkSettings settings,
  ) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(
      webVpnEnabledKey,
      settings.webVpnEnabled,
    );
    return settings;
  }

  Future<String?> loadThemeId() async {
    final prefs = await _preferencesLoader();
    return prefs.getString(themeIdKey);
  }

  Future<void> saveThemeId(String themeId) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(themeIdKey, themeId);
  }

  Future<bool> loadFollowSystemTheme() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(followSystemThemeKey) ?? false;
  }

  Future<void> saveFollowSystemTheme(bool enabled) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(followSystemThemeKey, enabled);
  }

  Future<AppTab> loadStartupTab() async {
    final prefs = await _preferencesLoader();
    return AppTab.fromStorageId(prefs.getString(startupTabKey));
  }

  Future<void> saveStartupTab(AppTab tab) async {
    final prefs = await _preferencesLoader();
    await prefs.setString(startupTabKey, tab.storageId);
  }

  Future<bool> loadStartupOnboardingCompleted() async {
    final prefs = await _preferencesLoader();
    return prefs.getBool(startupOnboardingCompletedKey) ?? false;
  }

  Future<void> saveStartupOnboardingCompleted(bool completed) async {
    final prefs = await _preferencesLoader();
    await prefs.setBool(startupOnboardingCompletedKey, completed);
  }
}
