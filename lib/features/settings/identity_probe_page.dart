import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/io_client.dart';

import '../../core/academic_url_resolver.dart';
import '../../core/client_backend_constants.dart';
import '../../data/services/academic_account_store.dart';
import '../../data/services/academic_auth_service.dart';
import '../../data/services/academic_progress_api_client.dart';
import '../../data/services/http_timeout.dart';

/// Manual experiment only. No school cookie is kept by this page after a run.
class IdentityProbePage extends StatefulWidget {
  const IdentityProbePage({super.key});

  @override
  State<IdentityProbePage> createState() => _IdentityProbePageState();
}

class _IdentityProbePageState extends State<IdentityProbePage> {
  final _accessCode = TextEditingController();
  bool _running = false;
  String? _result;

  @override
  void dispose() {
    _accessCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学号核验实验')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('此功能仅用于测试服务器能否凭当前教务会话读取学号。不会建立 ShuYo 账户，也不会改变校园登录状态。'),
          const SizedBox(height: 16),
          TextField(
            controller: _accessCode,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: '测试访问码',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _running ? null : _startProbe,
            child: Text(_running ? '测试中…' : '开始核验'),
          ),
          if (_result != null) ...[
            const SizedBox(height: 20),
            Text(_result!),
            const SizedBox(height: 12),
            const Text('测试结束后，请回到日程手动刷新课表，检查原有校园会话是否仍可用。'),
          ],
        ],
      ),
    );
  }

  Future<void> _startProbe() async {
    final accessCode = _accessCode.text.trim();
    if (accessCode.isEmpty) {
      setState(() => _result = '请填写测试访问码。');
      return;
    }
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('发送校园会话进行测试？'),
            content: const Text(
              '应用会把当前教务系统的会话 Cookie 临时发送至 ShuYo 服务器。'
              '服务器向学校查询学号后仅返回脱敏结果，不保存学校 Cookie。'
              '若会话已失效，测试会失败，但不会清除本地课表。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('同意并测试'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final studentId = await AcademicAccountStore().loadStudentId();
      if (!mounted) return;
      if (studentId == null) {
        setState(() => _result = '未找到当前登录学号，请先登录校园账户。');
        return;
      }
      final uri = AcademicUrlResolver.uri(
        AcademicProgressApiClient.studentIdentityPath,
      );
      final schoolCookie = await AcademicAuthService()
          .cookieHeaderForIdentityProbe(targetUri: uri);
      if (!mounted) return;
      if (schoolCookie == null || schoolCookie.isEmpty) {
        setState(() => _result = '未找到教务会话，请先重新登录校园账户。');
        return;
      }

      final rawClient = HttpClient()..connectionTimeout = HttpTimeout.connect;
      final client = IOClient(rawClient);
      try {
        final response = await HttpTimeout.request(
          client.post(
            Uri.parse(
                '${ClientBackendConstants.baseUrl}/api/v1/identity/probe'),
            headers: {
              'accept': 'application/json',
              'content-type': 'application/json; charset=utf-8',
              'x-identity-probe-key': accessCode,
            },
            body: jsonEncode({
              'schoolCookie': schoolCookie,
              'expectedStudentId': studentId,
            }),
          ),
          timeout: const Duration(seconds: 12),
          message: '核验请求超时',
        );
        if (!mounted) return;
        if (response.statusCode == 404) {
          setState(() => _result = '服务器暂未开启核验实验。');
          return;
        }
        if (response.statusCode == 403) {
          setState(() => _result = '测试访问码无效。');
          return;
        }
        if (response.statusCode == 429) {
          setState(() => _result = '测试次数过多，请稍后再试。');
          return;
        }
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 200 ||
            body is! Map ||
            body['data'] is! Map) {
          setState(() => _result = '服务器未返回可识别的结果。');
          return;
        }
        final data = body['data'] as Map;
        setState(() => _result = _describeResult(data));
      } finally {
        client.close();
        rawClient.close(force: true);
      }
    } on Object {
      if (mounted) setState(() => _result = '测试失败：网络连接或学校服务暂不可用。');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  String _describeResult(Map data) {
    switch (data['status']) {
      case 'verified':
        final masked = data['maskedStudentId']?.toString() ?? '未知';
        final matches = data['matchesLocal'] == true ? '一致' : '不一致';
        return '服务器读取到学号 $masked，与本机学号$matches。';
      case 'session_expired':
        return '学校返回登录跳转：当前教务会话可能已失效。';
      case 'school_rejected':
        return '学校拒绝了服务器查询。请检查手机上能否手动同步。';
      case 'no_student_id':
        return '学校返回了页面，但没有可识别的学号。';
      case 'school_unavailable':
      case 'network_error':
        return '服务器暂时无法从学校取得身份信息。';
      default:
        return '核验未完成（${data['status'] ?? '未知错误'}）。';
    }
  }
}
