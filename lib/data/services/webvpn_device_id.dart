import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// The device identity WebVPN expects on `auth/finish`.
///
/// The gateway's web app sends the FingerprintJS `visitorId` it stores in the
/// browser. The app has no browser fingerprint, so it sends a stable pseudo
/// identifier instead: a value that changed on every login would make the
/// gateway treat each attempt as a new device.
class WebVpnDeviceId {
  const WebVpnDeviceId._();

  static const storageKey = 'webvpn.auth.device_id';
  static final _pattern = RegExp(r'^[0-9a-f]{32}$');

  static Future<String> load({
    Future<SharedPreferences> Function()? preferencesLoader,
    Random? random,
  }) async {
    final preferences =
        await (preferencesLoader ?? SharedPreferences.getInstance)();
    final existing = preferences.getString(storageKey);
    if (existing != null && _pattern.hasMatch(existing)) return existing;
    final source = random ?? Random.secure();
    final value = List.generate(
      16,
      (_) => source.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await preferences.setString(storageKey, value);
    return value;
  }
}
