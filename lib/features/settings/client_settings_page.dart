import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/client_app_info.dart';
import '../../core/client_update_policy.dart';
import '../../data/repositories/client_backend_repository.dart';
import '../../data/services/academic_schedule_notification_service.dart';
import '../../data/services/app_store_version_service.dart';
import '../../data/services/client_settings_service.dart';
import '../../shared/shuyo_text_styles.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/client_update_prompt.dart';
import '../../shared/widgets/empty_state.dart';
import 'client_feedback_page.dart';

class ClientSettingsPage extends StatelessWidget {
  const ClientSettingsPage({
    super.key,
    required this.settingsService,
    required this.scheduleNotificationService,
    required this.backendRepository,
    required this.selectedThemeId,
    required this.followSystemTheme,
    required this.onThemeChanged,
    required this.onFollowSystemThemeChanged,
    this.isOnline = false,
    this.loadForumCacheSize,
    this.onClearForumCache,
    this.hasAcademicAccount = false,
    this.hasForumAccount = false,
    this.hasWebVpnSession = false,
    this.onAcademicLogout,
    this.onForumLogout,
    this.onWebVpnLogout,
    this.isDemo = false,
    this.onExitDemo,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;
  final ClientBackendRepository backendRepository;
  final String selectedThemeId;
  final bool followSystemTheme;
  final Future<void> Function(String themeId) onThemeChanged;
  final Future<void> Function(bool enabled) onFollowSystemThemeChanged;
  final bool isOnline;
  final Future<int> Function()? loadForumCacheSize;
  final Future<int> Function()? onClearForumCache;
  final bool hasAcademicAccount;
  final bool hasForumAccount;
  final bool hasWebVpnSession;
  final Future<bool> Function()? onAcademicLogout;
  final Future<bool> Function()? onForumLogout;
  final Future<bool> Function()? onWebVpnLogout;
  final bool isDemo;
  final Future<void> Function()? onExitDemo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _SettingsRow(
            title: '主题切换',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => _ThemeSettingsPage(
                  selectedThemeId: selectedThemeId,
                  followSystemTheme: followSystemTheme,
                  onThemeChanged: onThemeChanged,
                  onFollowSystemThemeChanged: onFollowSystemThemeChanged,
                ),
              ),
            ),
          ),
          _SettingsRow(
            title: '关于ShuYo',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(
                builder: (context) => _AboutClientPage(
                  backendRepository: backendRepository,
                  isDemo: isDemo,
                ),
              ),
            ),
          ),
          if (isDemo && onExitDemo != null)
            _SettingsRow(
              title: '退出演示',
              onTap: () => _exitDemo(context),
            ),
          _ForumCacheRow(
            loadSize: loadForumCacheSize,
            onClear: onClearForumCache,
          ),
          if (!isDemo &&
              (hasAcademicAccount || hasForumAccount || hasWebVpnSession))
            _AccountLogoutRow(
              hasAcademicAccount: hasAcademicAccount,
              hasForumAccount: hasForumAccount,
              hasWebVpnSession: hasWebVpnSession,
              onAcademicLogout: onAcademicLogout,
              onForumLogout: onForumLogout,
              onWebVpnLogout: onWebVpnLogout,
            ),
        ],
      ),
    );
  }

  Future<void> _exitDemo(BuildContext context) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('退出演示模式？'),
            content: const Text('退出后将返回正常登录流程，并清除本地演示数据。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出演示'),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) {
      await onExitDemo?.call();
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _ForumCacheRow extends StatefulWidget {
  const _ForumCacheRow({required this.loadSize, required this.onClear});

  final Future<int> Function()? loadSize;
  final Future<int> Function()? onClear;

  @override
  State<_ForumCacheRow> createState() => _ForumCacheRowState();
}

class _ForumCacheRowState extends State<_ForumCacheRow> {
  late Future<int> _sizeFuture;

  @override
  void initState() {
    super.initState();
    _sizeFuture = _loadSize();
  }

  @override
  void didUpdateWidget(covariant _ForumCacheRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loadSize != widget.loadSize) {
      _sizeFuture = _loadSize();
    }
  }

  Future<int> _loadSize() => widget.loadSize?.call() ?? Future<int>.value(0);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _sizeFuture,
      builder: (context, snapshot) {
        return _SettingsRow(
          title: '清除缓存',
          onTap: widget.onClear == null ? null : () => _confirm(context),
        );
      },
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final size = await _sizeFuture;
    if (!context.mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除缓存'),
        content: Text(
          '当前占用 ${_formatBytes(size)}。清除后将删除已缓存的帖子、私信、个人资料数据和图片，但不会退出登录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    final released = await widget.onClear?.call() ?? 0;
    if (context.mounted) {
      setState(() => _sizeFuture = _loadSize());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已释放 ${_formatBytes(released)}')),
      );
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _AccountLogoutRow extends StatefulWidget {
  const _AccountLogoutRow({
    required this.hasAcademicAccount,
    required this.hasForumAccount,
    required this.hasWebVpnSession,
    required this.onAcademicLogout,
    required this.onForumLogout,
    required this.onWebVpnLogout,
  });

  final bool hasAcademicAccount;
  final bool hasForumAccount;
  final bool hasWebVpnSession;
  final Future<bool> Function()? onAcademicLogout;
  final Future<bool> Function()? onForumLogout;
  final Future<bool> Function()? onWebVpnLogout;

  @override
  State<_AccountLogoutRow> createState() => _AccountLogoutRowState();
}

class _AccountLogoutRowState extends State<_AccountLogoutRow> {
  late bool _hasAcademicAccount;
  late bool _hasForumAccount;
  late bool _hasWebVpnSession;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    _hasAcademicAccount = widget.hasAcademicAccount;
    _hasForumAccount = widget.hasForumAccount;
    _hasWebVpnSession = widget.hasWebVpnSession;
  }

  @override
  void didUpdateWidget(covariant _AccountLogoutRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasAcademicAccount != widget.hasAcademicAccount) {
      _hasAcademicAccount = widget.hasAcademicAccount;
    }
    if (oldWidget.hasForumAccount != widget.hasForumAccount) {
      _hasForumAccount = widget.hasForumAccount;
    }
    if (oldWidget.hasWebVpnSession != widget.hasWebVpnSession) {
      _hasWebVpnSession = widget.hasWebVpnSession;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    final enabled = !_loggingOut &&
        ((_hasAcademicAccount && widget.onAcademicLogout != null) ||
            (_hasForumAccount && widget.onForumLogout != null) ||
            (_hasWebVpnSession && widget.onWebVpnLogout != null));
    return ListTile(
      title: Text('退出登录', style: TextStyle(color: colors.danger)),
      subtitle: _loggingOut ? const Text('正在退出...') : null,
      trailing: _loggingOut
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : const Icon(Icons.chevron_right),
      onTap: enabled ? _chooseAccount : null,
    );
  }

  Future<void> _chooseAccount() async {
    final target = await showModalBottomSheet<_LogoutTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = context.shuyoColors;
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Text(
                      '选择要退出的账户',
                      style: ShuYoTextStyles.sectionTitle(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.school_outlined),
                    title: const Text('上大校园账户'),
                    subtitle: Text(
                      _hasAcademicAccount ? '退出课表和校园服务' : '未登录',
                    ),
                    enabled:
                        _hasAcademicAccount && widget.onAcademicLogout != null,
                    onTap: _hasAcademicAccount &&
                            widget.onAcademicLogout != null
                        ? () =>
                            Navigator.of(context).pop(_LogoutTarget.academic)
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.forum_outlined),
                    title: const Text('乐乎账户'),
                    subtitle: Text(
                      _hasForumAccount ? '退出论坛' : '未登录',
                    ),
                    enabled: _hasForumAccount && widget.onForumLogout != null,
                    onTap: _hasForumAccount && widget.onForumLogout != null
                        ? () => Navigator.of(context).pop(_LogoutTarget.forum)
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.vpn_key_off_outlined),
                    title: const Text('WebVPN'),
                    subtitle: Text(
                      _hasWebVpnSession ? '重置WebVPN' : '未登录',
                    ),
                    enabled: _hasWebVpnSession && widget.onWebVpnLogout != null,
                    onTap: _hasWebVpnSession && widget.onWebVpnLogout != null
                        ? () => Navigator.of(context).pop(_LogoutTarget.webVpn)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (target == null || !mounted) return;
    await _confirmAndLogout(target);
  }

  Future<void> _confirmAndLogout(_LogoutTarget target) async {
    final academic = target == _LogoutTarget.academic;
    final forum = target == _LogoutTarget.forum;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              academic
                  ? '退出校园账户'
                  : forum
                      ? '退出乐乎论坛账户'
                      : '退出WebVPN',
            ),
            content: Text(
              academic
                  ? '退出后校园服务需重新登录\n\n已保存的课表信息不会被清除'
                  : forum
                      ? '退出后将清除论坛会话\n\n这不会影响校园账户'
                      : '退出后将关闭WebVPN并清除登录状态',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('退出'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;

    setState(() => _loggingOut = true);
    final loggedOut = switch (target) {
      _LogoutTarget.academic => await widget.onAcademicLogout?.call() ?? false,
      _LogoutTarget.forum => await widget.onForumLogout?.call() ?? false,
      _LogoutTarget.webVpn => await widget.onWebVpnLogout?.call() ?? false,
    };
    if (!mounted) return;
    setState(() {
      _loggingOut = false;
      if (loggedOut && academic) _hasAcademicAccount = false;
      if (loggedOut && forum) _hasForumAccount = false;
      if (loggedOut && target == _LogoutTarget.webVpn) {
        _hasWebVpnSession = false;
      }
    });
    if (loggedOut) {
      _showSnack(
        context,
        academic
            ? '已退出上大校园账户'
            : forum
                ? '已退出乐乎论坛账户'
                : '已退出WebVPN',
      );
    }
  }
}

enum _LogoutTarget { academic, forum, webVpn }

class _AboutClientPage extends StatefulWidget {
  const _AboutClientPage({
    required this.backendRepository,
    required this.isDemo,
  });

  final ClientBackendRepository backendRepository;
  final bool isDemo;

  @override
  State<_AboutClientPage> createState() => _AboutClientPageState();
}

class _AboutClientPageState extends State<_AboutClientPage> {
  static const _sourceUrl = 'https://github.com/shuosc/ShuYo';
  static const _licenseUrl =
      'https://github.com/shuosc/ShuYo/blob/main/LICENSE';
  static const _contributorsUrl =
      'https://github.com/shuosc/ShuYo/graphs/contributors';
  static const _termsUrl = 'https://shuyo.work/doc/terms.html';
  static const _privacyUrl = 'https://shuyo.work/doc/privacy.html';

  bool _checkingUpdate = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('关于ShuYo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/images/icon_light.png',
                      width: 96,
                      height: 96,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  ClientAppInfo.appName,
                  style: ShuYoTextStyles.title(
                    color: colors.textPrimary,
                    size: 22,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '版本 ${ClientAppInfo.version}（${ClientAppInfo.buildNumber}）',
                  style: ShuYoTextStyles.meta(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(),
          ),
          const _AboutGroupTitle('项目信息'),
          _AboutRow(
            icon: Icons.code,
            title: '源代码',
            subtitle: 'GitHub · shuosc/ShuYo',
            onTap: () => _openExternalUrl(_sourceUrl),
          ),
          _AboutRow(
            icon: Icons.balance_outlined,
            title: '开源许可',
            subtitle: 'GNU General Public License v3.0',
            onTap: () => _openExternalUrl(_licenseUrl),
          ),
          _AboutRow(
            icon: Icons.inventory_2_outlined,
            title: '第三方开源许可',
            onTap: _showThirdPartyLicenses,
          ),
          _AboutRow(
            icon: Icons.groups_outlined,
            title: '贡献者',
            subtitle: '查看 GitHub Contributors',
            onTap: () => _openExternalUrl(_contributorsUrl),
          ),
          const SizedBox(height: 18),
          const _AboutGroupTitle('隐私与声明'),
          _AboutRow(
            icon: Icons.security_outlined,
            title: '权限说明',
            onTap: () => Navigator.of(context).push<void>(
              shuyoRoute(builder: (context) => const _PermissionInfoPage()),
            ),
          ),
          _AboutRow(
            icon: Icons.description_outlined,
            title: '使用条款',
            onTap: () => _openExternalUrl(_termsUrl),
          ),
          _AboutRow(
            icon: Icons.privacy_tip_outlined,
            title: '隐私政策',
            onTap: () => _openExternalUrl(_privacyUrl),
          ),
          if (!widget.isDemo) ...[
            const SizedBox(height: 18),
            const _AboutGroupTitle('支持'),
            _AboutRow(
              icon: Icons.feedback_outlined,
              title: '问题与反馈',
              onTap: () => Navigator.of(context).push<void>(
                shuyoRoute(
                  builder: (context) => ClientFeedbackPage(
                    repository: widget.backendRepository,
                  ),
                ),
              ),
            ),
            _AboutRow(
              icon: Icons.system_update_outlined,
              title: '检查更新',
              trailing: _checkingUpdate
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : null,
              onTap: _checkingUpdate ? null : _checkForUpdate,
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Divider(),
          ),
          Text(
            '本应用是由学生开发的非官方开源工具，与上海大学、上海大学信息办无关，不属于官方软件。\n\n本应用仅作信息聚合展示。论坛相关功能遵守校内论坛的管理规则，用户在客户端产生的内容受论坛原有审核与管理制度约束。\n\n如果在客户端使用过程中出现问题，或是你希望有些新的功能，请通过“问题与反馈”联系开发者。\n～(∠・ω< )⌒☆',
            style: ShuYoTextStyles.bodyCompact(
              color: colors.textMuted,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExternalUrl(String url) async {
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted) _showSnack(context, '无法打开链接');
    } on Object {
      if (mounted) _showSnack(context, '无法打开链接');
    }
  }

  void _showThirdPartyLicenses() {
    showLicensePage(
      context: context,
      applicationName: ClientAppInfo.appName,
      applicationVersion:
          '${ClientAppInfo.version}（${ClientAppInfo.buildNumber}）',
      applicationIcon: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          'assets/images/icon_light.png',
          width: 48,
          height: 48,
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      if (ClientUpdatePolicy.source == ClientUpdateSource.appStore) {
        await _checkAppStoreForUpdate();
        return;
      }
      final update = await widget.backendRepository.checkForUpdate(
        forceRefresh: true,
      );
      if (!mounted) return;
      if (update == null) {
        _showSnack(context, '已是最新版本');
        return;
      }
      final openDownload = await showClientUpdatePrompt(
        context,
        update: update,
      );
      if (!mounted || !openDownload || !update.hasDownloadUrl) return;
      await _openDownload(update.downloadUrl);
    } on AppStoreVersionUnavailableException catch (error) {
      if (mounted) _showSnack(context, error.message);
    } on Object catch (error) {
      if (mounted) _showSnack(context, '检查更新失败：$error');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _checkAppStoreForUpdate() async {
    final update = await AppStoreVersionService().checkForUpdate();
    if (!mounted) return;
    if (update == null) {
      _showSnack(context, '已是最新版本');
      return;
    }
    final openAppStore = await showAppStoreUpdatePrompt(
      context,
      update: update,
    );
    if (!mounted || !openAppStore) return;
    await _openDownload(update.productUrl);
  }

  Future<void> _openDownload(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _showSnack(context, '下载链接无效');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _showSnack(context, '无法打开下载链接');
  }
}

class _AboutGroupTitle extends StatelessWidget {
  const _AboutGroupTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        title,
        style: ShuYoTextStyles.sectionTitle(
          color: context.shuyoColors.textPrimary,
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _PermissionInfoPage extends StatelessWidget {
  const _PermissionInfoPage();

  @override
  Widget build(BuildContext context) {
    final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
    return Scaffold(
      appBar: AppBar(title: const Text('权限说明')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '为了实现对应功能，ShuYo 可能会在你使用功能时申请以下权限。具体项目会因系统版本而异。',
            style: ShuYoTextStyles.bodyCompact(
              color: context.shuyoColors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          const _PermissionItem(
            icon: Icons.language,
            title: '网络访问',
            body: '用于访问校园服务、检查更新与提交反馈。',
          ),
          const _PermissionItem(
            icon: Icons.notifications_outlined,
            title: '通知',
            body: '用于发送上课提醒等你主动开启的通知。',
          ),
          _PermissionItem(
            icon: Icons.alarm_outlined,
            title: isIOS ? '闹钟' : '精确闹钟',
            body: isIOS ? '用于在支持 AlarmKit 的系统上为早课设置闹钟。' : '用于在设定时间准时触发课程提醒。',
          ),
          _PermissionItem(
            icon: Icons.photo_library_outlined,
            title: '照片与图片',
            body: isIOS
                ? '选图使用系统选择器，不需要读取整个相册；仅在保存图片时请求写入权限。'
                : '新版 Android 选图使用系统选择器；Android 9 及以下保存图片时可能需要存储权限。',
          ),
          if (!isIOS)
            const _PermissionItem(
              icon: Icons.restart_alt,
              title: '开机后恢复提醒',
              body: '用于设备重启后恢复已设置的课程提醒。',
            ),
          const SizedBox(height: 8),
          Text(
            '你可以在系统设置中随时查看或更改已授予的权限。拒绝某项权限只会影响对应功能。',
            style: ShuYoTextStyles.meta(
              color: context.shuyoColors.textMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(body),
      ),
    );
  }
}

class _ThemeSettingsPage extends StatefulWidget {
  const _ThemeSettingsPage({
    required this.selectedThemeId,
    required this.followSystemTheme,
    required this.onThemeChanged,
    required this.onFollowSystemThemeChanged,
  });

  final String selectedThemeId;
  final bool followSystemTheme;
  final Future<void> Function(String themeId) onThemeChanged;
  final Future<void> Function(bool enabled) onFollowSystemThemeChanged;

  @override
  State<_ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<_ThemeSettingsPage> {
  late String _selectedThemeId;
  late bool _followSystemTheme;
  String? _savingThemeId;
  bool _savingFollowSystemTheme = false;

  @override
  void initState() {
    super.initState();
    _selectedThemeId = widget.selectedThemeId;
    _followSystemTheme = widget.followSystemTheme;
  }

  @override
  void didUpdateWidget(covariant _ThemeSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedThemeId != oldWidget.selectedThemeId &&
        _savingThemeId == null) {
      _selectedThemeId = widget.selectedThemeId;
    }
    if (widget.followSystemTheme != oldWidget.followSystemTheme &&
        !_savingFollowSystemTheme) {
      _followSystemTheme = widget.followSystemTheme;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('主题切换')),
      body: ListView.separated(
        itemCount: ShuYoThemes.all.length + 1,
        separatorBuilder: (context, index) => Divider(color: colors.border),
        itemBuilder: (context, index) {
          if (index == 0) {
            return _SettingsSwitchRow(
              title: '跟随系统',
              value: _followSystemTheme,
              enabled: _savingThemeId == null && !_savingFollowSystemTheme,
              onChanged: _toggleFollowSystemTheme,
            );
          }
          final theme = ShuYoThemes.all[index - 1];
          final selected = theme.id == _selectedThemeId;
          return ListTile(
            selected: selected,
            selectedColor: colors.textPrimary,
            title: Text(
              theme.name,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            trailing: _ThemeSwatches(
              theme: theme,
              selected: selected,
              saving: _savingThemeId == theme.id,
            ),
            onTap: _savingThemeId == null ? () => _selectTheme(theme) : null,
          );
        },
      ),
    );
  }

  Future<void> _selectTheme(ShuYoThemeSpec theme) async {
    if ((!_followSystemTheme && _selectedThemeId == theme.id) ||
        _savingThemeId != null ||
        _savingFollowSystemTheme) {
      return;
    }
    setState(() {
      _selectedThemeId = theme.id;
      _followSystemTheme = false;
      _savingThemeId = theme.id;
    });
    try {
      await widget.onThemeChanged(theme.id);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(context, '主题保存失败：$error');
      setState(() {
        _selectedThemeId = widget.selectedThemeId;
        _followSystemTheme = widget.followSystemTheme;
      });
    } finally {
      if (mounted) {
        setState(() => _savingThemeId = null);
      }
    }
  }

  Future<void> _toggleFollowSystemTheme(bool enabled) async {
    if (_savingFollowSystemTheme || _savingThemeId != null) {
      return;
    }
    setState(() {
      _followSystemTheme = enabled;
      _savingFollowSystemTheme = true;
    });
    try {
      await widget.onFollowSystemThemeChanged(enabled);
      if (mounted && enabled) {
        final brightness = MediaQuery.platformBrightnessOf(context);
        setState(() {
          _selectedThemeId = ShuYoThemes.systemThemeIdFor(brightness);
        });
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      _showSnack(context, '主题保存失败：$error');
      setState(() {
        _followSystemTheme = widget.followSystemTheme;
        _selectedThemeId = widget.selectedThemeId;
      });
    } finally {
      if (mounted) {
        setState(() => _savingFollowSystemTheme = false);
      }
    }
  }
}

class _ThemeSwatches extends StatelessWidget {
  const _ThemeSwatches({
    required this.theme,
    required this.selected,
    required this.saving,
  });

  final ShuYoThemeSpec theme;
  final bool selected;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return SizedBox(
      width: 126,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (saving)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else if (selected)
            Icon(Icons.check, size: 20, color: colors.accent)
          else
            const SizedBox(width: 20),
          const SizedBox(width: 12),
          for (final color in theme.previewColors) ...[
            _ThemeSwatch(color: color),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      child: const SizedBox.square(dimension: 16),
    );
  }
}

class _NotificationSettingsPage extends StatefulWidget {
  const _NotificationSettingsPage({
    required this.settingsService,
    required this.scheduleNotificationService,
  });

  final ClientSettingsService settingsService;
  final AcademicScheduleNotificationService scheduleNotificationService;

  @override
  State<_NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<_NotificationSettingsPage> {
  late Future<ClientNotificationSettings> _future;
  ClientNotificationSettings? _settings;
  bool _saving = false;

  bool _alarmsSupported = false;
  AcademicScheduleAlarmSettings? _alarmSettings;
  bool _savingAlarm = false;
  String? _alarmRingtoneName;
  bool _pickingAlarmRingtone = false;

  @override
  void initState() {
    super.initState();
    _future = _loadSettings();
    _loadAlarmState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知设置')),
      body: FutureBuilder<ClientNotificationSettings>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 3));
          }
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.notifications_off,
              title: '设置加载失败',
              message: snapshot.error.toString(),
              action: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _future = _loadSettings();
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            );
          }
          final settings = _settings ?? snapshot.data!;
          final alarmSettings = _alarmSettings;
          return ListView(
            children: [
              _SettingsSwitchRow(
                title: '课表提醒',
                value: settings.scheduleEnabled,
                enabled: true,
                onChanged: (value) => _save(
                  settings.copyWith(scheduleEnabled: value),
                ),
              ),
              if (_alarmsSupported && alarmSettings != null) ...[
                _SettingsSwitchRow(
                  title: '早课闹钟',
                  subtitle: '每天仅为上午最早的一节课设置闹钟',
                  value: alarmSettings.enabled,
                  enabled: !_savingAlarm,
                  onChanged: (value) => _saveAlarm(
                    alarmSettings.copyWith(enabled: value),
                    requestPermission: value,
                  ),
                ),
                if (alarmSettings.enabled)
                  ListTile(
                    title: const Text('提前时间'),
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Text('${alarmSettings.leadMinutes} 分钟'),
                    ),
                    enabled: !_savingAlarm,
                    onTap: _savingAlarm
                        ? null
                        : () => _editAlarmLeadMinutes(alarmSettings),
                  ),
                if (alarmSettings.enabled &&
                    widget.scheduleNotificationService
                        .supportsAlarmRingtoneCustomization)
                  ListTile(
                    title: const Text('闹钟铃声'),
                    subtitle: Text(
                      _alarmRingtoneName ?? '默认',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _pickingAlarmRingtone
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : const Icon(Icons.chevron_right),
                    enabled: !_savingAlarm && !_pickingAlarmRingtone,
                    onTap: _pickAlarmRingtone,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<ClientNotificationSettings> _loadSettings() async {
    final settings = await widget.settingsService.loadNotificationSettings();
    _settings = settings;
    return settings;
  }

  Future<void> _loadAlarmState() async {
    final supported =
        await widget.scheduleNotificationService.supportsEarlyClassAlarms();
    final settings = supported
        ? await widget.scheduleNotificationService.loadAlarmSettings()
        : const AcademicScheduleAlarmSettings(
            enabled: false,
            leadMinutes: 20,
          );
    final ringtoneName = supported
        ? await widget.scheduleNotificationService.loadAlarmRingtoneName()
        : null;
    if (!mounted) return;
    setState(() {
      _alarmsSupported = supported;
      _alarmSettings = settings;
      _alarmRingtoneName = ringtoneName;
    });
  }

  Future<void> _save(ClientNotificationSettings settings) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _settings = settings;
    });
    try {
      final saved =
          await widget.settingsService.saveNotificationSettings(settings);
      await widget.scheduleNotificationService.syncScheduleReminders(
        requestPermission: saved.scheduleEnabled,
      );
      if (!mounted) {
        return;
      }
      setState(() => _settings = saved);
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '设置保存失败：$error');
        setState(() {
          _future = _loadSettings();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _saveAlarm(
    AcademicScheduleAlarmSettings settings, {
    bool requestPermission = false,
  }) async {
    if (_savingAlarm) {
      return;
    }
    setState(() {
      _savingAlarm = true;
      _alarmSettings = settings;
    });
    try {
      final saved =
          await widget.scheduleNotificationService.saveAlarmSettingsAndSync(
        settings,
        requestPermission: requestPermission,
      );
      if (!mounted) {
        return;
      }
      setState(() => _alarmSettings = saved);
      if (settings.enabled && !saved.enabled) {
        _showSnack(context, '未获得闹钟权限，请在系统设置中允许 ShuYo 使用闹钟');
      }
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '闹钟设置保存失败：$error');
        _loadAlarmState();
      }
    } finally {
      if (mounted) {
        setState(() => _savingAlarm = false);
      }
    }
  }

  Future<void> _editAlarmLeadMinutes(
    AcademicScheduleAlarmSettings settings,
  ) async {
    final formKey = GlobalKey<FormState>();
    var input = settings.leadMinutes.toString();
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('提前时间'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: input,
            onChanged: (value) => input = value,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '提前分钟数',
              helperText: '可设置 1–120 分钟',
            ),
            validator: (text) {
              final minutes = int.tryParse(text ?? '');
              if (minutes == null || minutes < 1 || minutes > 120) {
                return '请输入 1–120 之间的整数';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(dialogContext).pop(int.parse(input));
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value != null && mounted) {
      await _saveAlarm(settings.copyWith(leadMinutes: value));
    }
  }

  Future<void> _pickAlarmRingtone() async {
    if (_pickingAlarmRingtone || _savingAlarm) {
      return;
    }
    setState(() => _pickingAlarmRingtone = true);
    try {
      final name = await widget.scheduleNotificationService.pickAlarmRingtone();
      if (!mounted || name == null) {
        return;
      }
      setState(() => _alarmRingtoneName = name);
      _showSnack(context, '闹钟铃声已设置为$name');
    } on Object catch (error) {
      if (mounted) {
        _showSnack(context, '选择闹钟铃声失败：$error');
      }
    } finally {
      if (mounted) {
        setState(() => _pickingAlarmRingtone = false);
      }
    }
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return SwitchListTile(
      title: Text(
        title,
        style: TextStyle(
          color: enabled ? colors.textPrimary : colors.textMuted,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(color: colors.textMuted),
            ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
