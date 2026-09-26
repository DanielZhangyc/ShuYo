import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/forum_constants.dart';
import '../../core/forum_url_resolver.dart';
import '../../core/wecom_constants.dart';
import '../../data/services/wecom_auth_service.dart';

/// 企业微信扫码登录等待页。
///
/// 展示二维码图片，并支持点击拉起企业微信确认页。在后台长轮询
/// 等待用户扫码确认，成功后返回换取到的 SSO 会话结果。
class WeComScanPage extends StatefulWidget {
  const WeComScanPage({
    super.key,
    required this.session,
    required this.authService,
    required this.target,
  });

  final WeComQrSession session;
  final WeComAuthService authService;

  /// 本次扫码要登录的目标系统，决定 SSO 下发授权码的归属。
  final WeComOAuthTarget target;

  @override
  State<WeComScanPage> createState() => _WeComScanPageState();
}

class _WeComScanPageState extends State<WeComScanPage> {
  WeComScanStatus _status = WeComScanStatus.waiting;
  bool _launchingLink = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    unawaited(_waitForScan());
  }

  @override
  void dispose() {
    // 页面被销毁时取消后台长轮询，避免在后台继续发起网络请求。
    _cancelled = true;
    super.dispose();
  }

  /// 后台长轮询，状态变化时刷新界面，成功后换取目标业务系统回调地址。
  Future<void> _waitForScan() async {
    final result = await widget.authService.waitForScan(
      widget.session.key,
      isCancelled: () => _cancelled,
      onStatusChanged: (status) {
        if (mounted && status != _status) {
          setState(() => _status = status);
        }
      },
    );
    if (!mounted) return;
    if (!result.isSuccess) {
      _showError('二维码已过期或已取消，请重新尝试');
      return;
    }
    try {
      // 阶段一：auth_code → SSO 会话（state 固定为教务参数）。
      await widget.authService.redeem(
        result.authCode!,
        WeComAuthService.weComRedeemState,
      );
      if (mounted) {
        setState(() => _status = WeComScanStatus.succeeded);
      }
      // WebVPN 的 OAuth callback 只是 SPA 入口，还必须在同一原生
      // Cookie 会话中完成 auth/finish 并用 user/info 确认身份。
      if (widget.target.kind == WeComOAuthTargetKind.webVpn) {
        final webVpnResult = await widget.authService.completeWebVpnLogin();
        if (!mounted) return;
        Navigator.of(context).pop(webVpnResult);
        return;
      }
      // 阶段二：SSO 会话 → 目标业务系统授权码回调。
      //
      // 需要 state 预热的系统（如论坛）改由 WebView 自行走入口到回调的链路：
      // 它的 `_forum_session` 保存着 OAuth CSRF state，若经插件拷贝进 WebView
      // 会被重新编码而损坏，导致 Discourse 返回 csrf_detected。让浏览器自己
      // 持有该 cookie，等价于全程复用同一个会话。
      final bootstrapUrl = widget.target.stateBootstrapUrl;
      final needsBootstrap = bootstrapUrl != null && bootstrapUrl.isNotEmpty;
      final rawCallbackUri = needsBootstrap
          ? Uri.parse(bootstrapUrl)
          : await widget.authService.authorizeTarget(widget.target);
      if (!mounted) return;
      // 两条分支拿到的都是**直连域名**（目标系统的 redirect_uri 是注册在
      // SSO 侧的固定值，不能改写）。开启 WebVPN 时必须换成代理域名，
      // 否则 WebView 会去加载校外不可达的地址。
      final callbackUri = Uri.parse(
        ForumUrlResolver.resolve(rawCallbackUri.toString()),
      );
      // 自举时论坛会重新下发 _forum_session，无需携带已损坏的副本。
      final cookies = widget.authService.cookieJar
          .where((entry) =>
              !needsBootstrap ||
              entry.cookie.name != ForumConstants.sessionCookieName)
          .toList();
      Navigator.of(context).pop(
        WeComRedeemResult(
          callbackUri: callbackUri,
          sessionCookies: cookies,
        ),
      );
    } on WeComAuthException catch (error) {
      if (mounted) {
        _showError(error.message);
      }
    } on Object {
      if (mounted) {
        _showError('企业微信授权失败，请重新尝试');
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
  }

  /// 调用系统打开 wxwork:// scheme（或复制链接）。
  Future<void> _openWeCom() async {
    if (_launchingLink) return;
    setState(() => _launchingLink = true);
    try {
      final ok = await launchUrl(
        Uri.parse(widget.session.wxWorkSchemeUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        await Clipboard.setData(
          ClipboardData(text: widget.session.confirmUrl),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法打开企业微信，已复制链接，请手动打开')),
          );
        }
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开企业微信，请手动打开企业微信')),
        );
      }
    } finally {
      if (mounted) setState(() => _launchingLink = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('企业微信登录'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Text(
                '使用企业微信扫一扫',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Text(
                '打开手机企业微信，点击右上角扫码，或点击下方按钮直接唤起企业微信。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 220,
                  height: 220,
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: Image.network(
                    widget.session.qrImageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.broken_image_outlined, size: 48),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _statusWidget(),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _launchingLink ? null : _openWeCom,
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开企业微信登录'),
              ),
              const SizedBox(height: 8),
              Text(
                '扫码确认后请返回本应用',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusWidget() {
    final (text, icon) = switch (_status) {
      WeComScanStatus.waiting => (
          '等待扫码…',
          Icons.schedule,
        ),
      WeComScanStatus.confirmedPending => (
          '已扫码，请在手机企业微信确认',
          Icons.android,
        ),
      WeComScanStatus.succeeded => (
          '登录成功',
          Icons.check_circle,
        ),
      WeComScanStatus.expired => (
          '二维码已过期',
          Icons.error_outline,
        ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
