import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/core/app_tab.dart';
import 'package:shuyo/data/services/client_settings_service.dart';
import 'package:shuyo/data/services/academic_native_auth_service.dart';
import 'package:shuyo/data/services/verification_delivery_service.dart';

void main() {
  test('WebVPN is disabled by default and preserves an explicit opt-in',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect((await service.loadNetworkSettings()).webVpnEnabled, isFalse);

    await service.saveNetworkSettings(
      const ClientNetworkSettings(webVpnEnabled: true),
    );
    expect((await service.loadNetworkSettings()).webVpnEnabled, isTrue);
  });

  test('startup onboarding completion is stored independently', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect(await service.loadStartupOnboardingCompleted(), isFalse);
    await service.saveStartupOnboardingCompleted(true);
    expect(await service.loadStartupOnboardingCompleted(), isTrue);
  });

  test('startup display defaults to home and stores stable tab IDs', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ClientSettingsService();

    expect(await service.loadStartupTab(), AppTab.home);
    await service.saveStartupTab(AppTab.progress);
    expect(await service.loadStartupTab(), AppTab.progress);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ClientSettingsService.startupTabKey), 'progress');
    await prefs.setString(ClientSettingsService.startupTabKey, 'removed-tab');
    expect(await service.loadStartupTab(), AppTab.home);
  });

  test('verification delivery alternates methods between login flows',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = VerificationDeliveryService();
    const methods = AcademicVerificationMethod.values;

    expect(
      await service.preferredMethod(methods),
      AcademicVerificationMethod.wecom,
    );
    await service.markSent(AcademicVerificationMethod.wecom);
    expect(
      await service.preferredMethod(methods),
      AcademicVerificationMethod.sms,
    );
    expect(
      await service.remainingCooldown(AcademicVerificationMethod.wecom),
      greaterThan(Duration.zero),
    );
  });
}
