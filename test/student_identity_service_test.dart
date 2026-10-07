import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shuyo/data/services/academic_account_store.dart';
import 'package:shuyo/data/services/academic_auth_service.dart';
import 'package:shuyo/data/services/secure_app_store.dart';
import 'package:shuyo/data/services/student_identity_service.dart';

class _MemorySecureStore extends SecureAppStore {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _SchoolAuth extends AcademicAuthService {
  _SchoolAuth()
      : super(cookieLoader: (_) async => const [], cookieSetter: (_) async {});

  int reads = 0;

  @override
  Future<String?> cookieHeaderForIdentityVerification(
      {required Uri targetUri}) async {
    reads++;
    return 'JSESSIONID=school-session';
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('binds only after consent, then reuses the ShuYo session', () async {
    final secure = _MemorySecureStore();
    final school = _SchoolAuth();
    final accounts = AcademicAccountStore();
    await accounts.saveStudentId('23123456');
    var enrollmentCount = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/student/sessions') {
        enrollmentCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['schoolCookie'], 'JSESSIONID=school-session');
        expect(body['expectedStudentId'], '23123456');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'token': 'a' * 43,
              'maskedStudentId': '23****56',
              'expiresAt': '2099-01-01T00:00:00Z',
            }
          }),
          201,
        );
      }
      return http.Response('{}', 500);
    });
    final service = StudentIdentityService(
      secureStore: secure,
      accountStore: accounts,
      academicAuthService: school,
      httpClient: client,
    );
    await service.ensureAfterCampusLogin();
    expect(school.reads, 0);
    await service.grantConsent();
    await service.ensureAfterCampusLogin();
    expect(school.reads, 1);
    expect(enrollmentCount, 1);
    expect((await service.loadLocalSession())?.studentId, '23123456');
    await service.ensureAfterCampusLogin();
    expect(enrollmentCount, 1);
    service.dispose();
  });
}
