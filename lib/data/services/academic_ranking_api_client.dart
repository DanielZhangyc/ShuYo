import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_user_agent.dart';
import '../models/academic_ranking.dart';
import 'academic_auth_service.dart';
import 'academic_ranking_parser.dart';
import 'academic_schedule_api_client.dart';
import 'http_timeout.dart';

class AcademicRankingApiClient {
  AcademicRankingApiClient({
    AcademicAuthService? authService,
    http.Client? httpClient,
  })  : _authService = authService ?? AcademicAuthService(),
        _httpClient = httpClient ?? IOClient(HttpClient());

  static const _indexPath =
      '/jwglxt/cjpmtj/cjpmtj_cxLnCjpmcxIndex.html?gnmkdm=N309107&layout=default';
  static const _queryPath =
      '/jwglxt/cjpmtj/cjpmtj_cxLnCjpmcxIndex.html?doType=query&gnmkdm=N309107';

  final AcademicAuthService _authService;
  final http.Client _httpClient;

  Future<AcademicRanking> fetchCurrentRanking({
    String expectedStudentId = '',
  }) async {
    final indexUri = AcademicUrlResolver.uri(_indexPath);
    final cookie = await _authService.cookieHeader(targetUri: indexUri);
    if (cookie == null || cookie.isEmpty) {
      throw const AcademicAuthException('请先登录上大校园账户');
    }
    final indexResponse = await HttpTimeout.request(
      _httpClient.get(
        indexUri,
        headers: _headers(cookie: cookie, referer: indexUri),
      ),
      message: '排名页面请求超时，请稍后重试',
    );
    _ensureResponse(indexResponse);
    final queryResponse = await HttpTimeout.request(
      _httpClient.post(
        AcademicUrlResolver.uri(_queryPath),
        headers: _headers(cookie: cookie, referer: indexUri, form: true),
        body: {
          '_search': 'false',
          'nd': DateTime.now().millisecondsSinceEpoch.toString(),
          'queryModel.showCount': '15',
          'queryModel.currentPage': '1',
          'queryModel.sortName': ' ',
          'queryModel.sortOrder': 'asc',
          'time': '0',
        },
      ),
      message: '排名数据请求超时，请稍后重试',
    );
    _ensureResponse(queryResponse);
    return AcademicRankingParser.parse(
      queryResponse.body,
      expectedStudentId: expectedStudentId,
    );
  }

  Map<String, String> _headers({
    required String cookie,
    required Uri referer,
    bool form = false,
  }) =>
      {
        'accept': form
            ? 'application/json, text/javascript, */*; q=0.01'
            : 'text/html,application/xhtml+xml',
        'cookie': cookie,
        'referer': referer.toString(),
        'user-agent': ClientUserAgent.mobileBrowser,
        if (form) ...{
          'content-type': 'application/x-www-form-urlencoded;charset=UTF-8',
          'x-requested-with': 'XMLHttpRequest',
        },
      };

  void _ensureResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw AcademicAuthException('教务登录已失效', response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AcademicApiException(
        '教务系统排名请求失败',
        statusCode: response.statusCode,
      );
    }
    final lower = response.body.toLowerCase();
    if (lower.contains('/oauth2/login') ||
        lower.contains('newsso.shu.edu.cn') ||
        lower.contains('jwglxt/xtgl/login_slogin') ||
        lower.contains('name="yhm"')) {
      throw const AcademicAuthException('教务登录已失效，请重新登录');
    }
  }
}
