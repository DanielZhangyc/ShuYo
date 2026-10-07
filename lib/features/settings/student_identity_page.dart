import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/services/student_identity_service.dart';

class StudentIdentityPage extends StatefulWidget {
  const StudentIdentityPage({super.key, required this.service});

  final StudentIdentityService service;

  @override
  State<StudentIdentityPage> createState() => _StudentIdentityPageState();
}

class _StudentIdentityPageState extends State<StudentIdentityPage> {
  late Future<StudentIdentitySession?> _session = _load();
  bool _busy = false;
  String? _message;

  Future<StudentIdentitySession?> _load() async {
    try {
      return await widget.service.checkCurrentSession();
    } on Object {
      return widget.service.loadLocalSession();
    }
  }

  void _refresh() {
    if (mounted) setState(() => _session = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShuYo 身份')),
      body: FutureBuilder<StudentIdentitySession?>(
        future: _session,
        builder: (context, snapshot) {
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final session = snapshot.data;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                  session == null ? '未认证' : '已认证 · ${session.maskedStudentId}'),
              if (session == null) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _verify,
                  child: const Text('尝试认证'),
                ),
              ],
              if (session != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _busy ? null : _signOut,
                  child: const Text('退出这台设备'),
                ),
                TextButton(
                  onPressed: _busy ? null : _revokeAll,
                  child: const Text('退出所有设备'),
                ),
                TextButton(
                  onPressed: _busy ? null : _deleteAccount,
                  child: const Text('删除 ShuYo 账户'),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 16),
                Text(_message!),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await widget.service.hasConsent()) {
        if (!mounted || !await _confirmIdentityConsent()) return;
        await widget.service.grantConsent();
      }
      await widget.service.bindCurrentStudent();
      if (mounted) setState(() => _message = '身份已认证');
      _refresh();
    } on Object {
      if (mounted) {
        setState(() => _message = '当前暂时无法验证您的身份，请稍后再试');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirmIdentityConsent() async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('身份验证'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '为避免身份冒用，ShuYo将验证你的校园身份，认证后可使用分享课程表、课程评价等功能。',
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://shuyo.work/doc/privacy.html'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('隐私政策'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('暂不'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    try {
      await widget.service.signOut();
      if (mounted) setState(() => _message = '已退出这台设备的 ShuYo 身份。');
      _refresh();
    } on Object {
      if (mounted) setState(() => _message = '退出失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeAll() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出所有设备？'),
            content: const Text('所有设备上的 ShuYo 身份都会失效；以后需重新登录学校并核实学号。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出所有设备'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.revokeAllDevices();
      if (mounted) setState(() => _message = '所有设备已退出。');
      _refresh();
    } on StudentIdentityException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) setState(() => _message = '操作失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('删除 ShuYo 账户？'),
            content: const Text(
              '将删除服务器保存的加密学号与所有设备的 ShuYo 身份。'
              '不会删除校园账户或手机上的课表。此操作不能撤销。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('删除账户'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.deleteAccount();
      if (mounted) setState(() => _message = 'ShuYo 账户已删除。');
      _refresh();
    } on StudentIdentityException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) setState(() => _message = '删除失败，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
