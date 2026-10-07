import 'package:flutter/material.dart';

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
              Text(session == null
                  ? '尚未核实学号'
                  : '已核实学号 ${session.maskedStudentId}'),
              const SizedBox(height: 10),
              Text(session == null
                  ? '校园登录和本地课表不受影响。核实学号后，可在后续版本中用同一账户管理反馈与课表分享。'
                  : '这台设备的 ShuYo 身份有效至 ${_date(session.expiresAt)}。学校会话失效不会立即退出 ShuYo 身份。'),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: Text(session == null ? '核实当前学号' : '重新核实学号'),
              ),
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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('核实学号'),
            content: const Text(
              'ShuYo 会将当前教务会话临时发送到自己的服务器，用于向学校核实学号。'
              '服务器不保存学校会话；会加密保存真实学号，总管理员可按需查看。'
              '这台设备的 ShuYo 身份最长保留 90 天，可随时退出。'
              '核验失败不影响校园登录或本地课表。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('同意并核实'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.service.grantConsent();
      final session = await widget.service.bindCurrentStudent(force: true);
      if (mounted) setState(() => _message = '核实成功：${session.maskedStudentId}');
      _refresh();
    } on StudentIdentityException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } on Object {
      if (mounted) setState(() => _message = '暂时无法核实学号，请稍后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  String _date(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
