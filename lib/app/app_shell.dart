import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/classroom_url_resolver.dart';
import '../core/client_app_info.dart';
import '../core/client_update_policy.dart';
import '../data/demo/demo_data_bundle.dart';
import '../data/demo/demo_repositories.dart';
import '../data/models/client_backend.dart';
import '../data/repositories/academic_schedule_repository.dart';
import '../data/repositories/announcement_repository.dart';
import '../data/repositories/classroom_repository.dart';
import '../data/repositories/client_backend_repository.dart';
import '../data/repositories/course_rating_repository.dart';
import '../data/services/academic_account_store.dart';
import '../data/services/academic_auth_service.dart';
import '../data/services/academic_schedule_api_client.dart';
import '../data/services/academic_schedule_display_settings_service.dart';
import '../data/services/academic_schedule_notification_service.dart';
import '../data/services/academic_schedule_widget_service.dart';
import '../data/services/client_settings_service.dart';
import '../data/services/webvpn_session_store.dart';
import '../features/auth/native_login_page.dart';
import '../features/home/academic_schedule_page.dart';
import '../features/home/announcements_page.dart';
import '../features/home/course_rating_page.dart';
import '../features/home/empty_classroom_page.dart';
import '../features/home/home_dashboard_page.dart';
import '../features/onboarding/startup_onboarding.dart';
import '../features/settings/client_settings_page.dart';
import '../shared/navigation/shuyo_route.dart';
import '../shared/theme/shuyo_theme.dart';
import '../shared/widgets/app_header.dart';
import '../shared/widgets/client_update_prompt.dart';
import '../shared/widgets/info_confirm_dialog.dart';
import '../shared/widgets/shuyo_launch_surface.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.initialWebVpnEnabled,
    required this.selectedThemeId,
    required this.followSystemTheme,
    required this.onThemeChanged,
    required this.onFollowSystemThemeChanged,
    required this.academicLoginSignal,
    required this.initialHasAcademicSession,
    required this.initialAcademicStudentId,
    required this.onboardingController,
    this.initialOpenSchedule = false,
    this.initialScheduleState,
    this.initialScheduleDisplayState,
    this.initialScheduleLoadError,
    this.isDemo = false,
    this.demoData,
    this.onExitDemo,
  });

  final bool initialWebVpnEnabled;
  final String selectedThemeId;
  final bool followSystemTheme;
  final Future<void> Function(String) onThemeChanged;
  final Future<void> Function(bool) onFollowSystemThemeChanged;
  final int academicLoginSignal;
  final bool initialHasAcademicSession;
  final String? initialAcademicStudentId;
  final StartupOnboardingController onboardingController;
  final bool initialOpenSchedule;
  final AcademicScheduleCacheState? initialScheduleState;
  final AcademicScheduleDisplayState? initialScheduleDisplayState;
  final String? initialScheduleLoadError;
  final bool isDemo;
  final DemoDataBundle? demoData;
  final Future<void> Function()? onExitDemo;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  static const _exitBackPressInterval = Duration(seconds: 2);
  static const _webVpnStatusRefreshInterval = Duration(minutes: 5);

  int _tabIndex = 0;
  late bool _webVpnEnabled = widget.initialWebVpnEnabled;
  late bool _hasAcademicSession = widget.initialHasAcademicSession;
  late String? _academicStudentId = widget.initialAcademicStudentId;
  bool _syncingAcademicSchedule = false;
  bool _loadingScheduleSummary = false;
  bool _loadingAnnouncementSummary = false;
  bool _checkingClientBackendPrompts = false;
  bool _refreshingWebVpnStatus = false;
  bool _openingScheduleFromWidget = false;
  bool _hideShellForInitialWidgetLaunch = false;
  String _scheduleSummaryText = '正在读取课表...';
  String _announcementSummaryText = '正在读取通知公告...';
  DateTime? _lastWebVpnStatusFetchAttempt;
  DateTime? _lastExitBackAt;
  WebVpnServiceStatus _webVpnServiceStatus =
      const WebVpnServiceStatus.unknown();
  Timer? _scheduleSummaryTimer;
  Timer? _announcementSummaryTimer;
  StreamSubscription<Uri?>? _widgetClickSubscription;

  late final AcademicScheduleRepository _scheduleRepository;
  late final AcademicScheduleNotificationService _scheduleNotificationService;
  late final AcademicScheduleWidgetService _scheduleWidgetService;
  late final AnnouncementRepository _announcementRepository;
  late ClassroomRepository _classroomRepository;
  late final CourseRatingRepository _courseRatingRepository;
  final _clientSettingsService = ClientSettingsService();
  final _clientBackendRepository = ClientBackendRepository();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hideShellForInitialWidgetLaunch = widget.initialOpenSchedule;
    final demo = widget.demoData;
    _scheduleRepository = widget.isDemo && demo != null
        ? DemoAcademicScheduleRepository(demo.schedule)
        : AcademicScheduleRepository();
    _scheduleNotificationService =
        AcademicScheduleNotificationService(repository: _scheduleRepository);
    _scheduleWidgetService =
        AcademicScheduleWidgetService(repository: _scheduleRepository);
    _announcementRepository = widget.isDemo && demo != null
        ? DemoAnnouncementRepository(
            items: demo.announcements,
            details: demo.announcementDetails,
          )
        : AnnouncementRepository();
    _classroomRepository = widget.isDemo && demo != null
        ? DemoClassroomRepository(
            options: demo.classroomOptions,
            schedule: demo.classroomSchedule,
          )
        : ClassroomRepository();
    _courseRatingRepository = widget.isDemo && demo != null
        ? DemoCourseRatingRepository(demo.courseRatings)
        : CourseRatingRepository();
    widget.onboardingController.setAccountLogoutHandlers(
      onAcademicLogout: _logoutAcademicAccount,
    );
    widget.onboardingController
        .setWebVpnChangeHandler(_changeWebVpnFromAccountManager);
    _syncOnboardingAccountStatus();
    unawaited(_refreshScheduleSummaryQuietly());
    unawaited(_loadAnnouncementSummaryFromCache());
    if (Platform.isAndroid || Platform.isIOS) {
      _widgetClickSubscription = HomeWidget.widgetClicked.listen((uri) {
        if (uri?.scheme == 'shuyo' && uri?.host == 'schedule') {
          unawaited(_openScheduleFromWidget());
        }
      });
      if (widget.initialOpenSchedule) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_openScheduleFromWidget(initialLaunch: true));
        });
      }
    }
    if (!widget.isDemo) {
      _scheduleSummaryTimer = Timer.periodic(
        const Duration(minutes: 1),
        (_) => unawaited(_refreshScheduleSummaryQuietly()),
      );
      _announcementSummaryTimer = Timer.periodic(
        AnnouncementRepository.defaultAutoRefreshInterval,
        (_) => unawaited(_refreshAnnouncementSummaryQuietly()),
      );
      unawaited(_scheduleNotificationService.syncScheduleReminders());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_refreshAnnouncementSummaryQuietly());
        unawaited(_checkClientBackendPrompts());
      });
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.academicLoginSignal != oldWidget.academicLoginSignal) {
      unawaited(_finishAcademicLogin());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.isDemo || state != AppLifecycleState.resumed) return;
    unawaited(_refreshScheduleSummaryQuietly());
    unawaited(_refreshAnnouncementSummaryQuietly());
    unawaited(_scheduleNotificationService.syncScheduleReminders());
    final last = _lastWebVpnStatusFetchAttempt;
    if (last == null ||
        DateTime.now().difference(last) >= _webVpnStatusRefreshInterval) {
      unawaited(_refreshWebVpnStatus());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scheduleSummaryTimer?.cancel();
    _announcementSummaryTimer?.cancel();
    _widgetClickSubscription?.cancel();
    widget.onboardingController.setWebVpnChangeHandler(null);
    widget.onboardingController.setAccountLogoutHandlers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hideShellForInitialWidgetLaunch) {
      return ShuYoLaunchSurface(
        theme: ShuYoThemes.byId(widget.selectedThemeId),
      );
    }
    const titles = ['首页', '评教', '地图', '日程'];
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _handleRootPop();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              AppHeader(
                title: titles[_tabIndex],
                showSettings: true,
                onSettings: _openClientSettings,
                onNotification: _openNotifications,
              ),
              Expanded(
                child: IndexedStack(
                  index: _tabIndex,
                  children: [
                    _homeBody(),
                    const SizedBox.expand(),
                    const SizedBox.expand(),
                    const SizedBox.expand(),
                  ],
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _tabIndex,
          type: BottomNavigationBarType.fixed,
          onTap: (index) {
            setState(() => _tabIndex = index);
            if (index == 0) {
              unawaited(_refreshScheduleSummaryQuietly());
              unawaited(_refreshAnnouncementSummaryQuietly());
            }
          },
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: '首页'),
            BottomNavigationBarItem(
                icon: Icon(Icons.rate_review_outlined), label: '评教'),
            BottomNavigationBarItem(
                icon: Icon(Icons.map_outlined), label: '地图'),
            BottomNavigationBarItem(
                icon: Icon(Icons.calendar_month), label: '日程'),
          ],
        ),
      ),
    );
  }

  void _handleRootPop() {
    if (widget.onboardingController.dismissAccountManager()) return;
    final now = DateTime.now();
    if (_lastExitBackAt != null &&
        now.difference(_lastExitBackAt!) <= _exitBackPressInterval) {
      SystemNavigator.pop();
      return;
    }
    _lastExitBackAt = now;
    _showSnack('再按一次退出 ShuYo');
  }

  Widget _homeBody() => HomeDashboardPage(
        hasAcademicAccount: _hasAcademicSession,
        academicStudentId: _academicStudentId,
        isAcademicLoginCompleting: _syncingAcademicSchedule,
        onLogin: _openAccountManager,
        onOpenAcademicSystem: _syncingAcademicSchedule
            ? () => _showSnack('正在获取课表，请稍后')
            : () => unawaited(_openAcademicSystem()),
        onOpenAnnouncements: () => unawaited(_openAnnouncements()),
        onOpenEmptyClassroom: () => unawaited(_openEmptyClassroom()),
        onOpenCourseRatings: () => unawaited(_openCourseRatings()),
        todayCourseContent: _scheduleSummaryText,
        announcementContent: _announcementSummaryText,
        isDemo: widget.isDemo,
      );

  void _openNotifications() {
    Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('通知')),
          body: const SizedBox.expand(),
        ),
      ),
    );
  }

  void _openAccountManager() {
    if (widget.isDemo) {
      _showSnack('请在设置中退出演示模式');
      return;
    }
    widget.onboardingController.openAccountManager(
      academicLoggedIn: _hasAcademicSession,
      webVpnEnabled: _webVpnEnabled,
      webVpnServiceStatus: _webVpnServiceStatus,
    );
    unawaited(_refreshWebVpnStatus());
  }

  void _syncOnboardingAccountStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onboardingController.updateAccountStatus(
        academicLoggedIn: _hasAcademicSession,
        webVpnEnabled: _webVpnEnabled,
        webVpnServiceStatus: _webVpnServiceStatus,
      );
    });
  }

  Future<void> _finishAcademicLogin() async {
    if (widget.isDemo) return;
    setState(() => _hasAcademicSession = true);
    await _loadAcademicStudentId();
    _syncOnboardingAccountStatus();
    try {
      final auth = AcademicAuthService();
      await auth.markLoggedIn();
      await auth.cookieHeader();
    } on Object {
      // The login succeeded; a temporary WebView cookie delay is recoverable.
    }
    await _syncScheduleAfterAcademicLogin();
  }

  Future<void> _loadAcademicStudentId() async {
    final studentId = await AcademicAccountStore().loadStudentId();
    if (mounted) setState(() => _academicStudentId = studentId);
  }

  Future<bool> _syncScheduleAfterAcademicLogin() async {
    if (widget.isDemo || _syncingAcademicSchedule) return false;
    setState(() {
      _syncingAcademicSchedule = true;
      _scheduleSummaryText = '课表获取中...';
    });
    try {
      await _scheduleRepository.refreshSchedule();
      final schedule = await _scheduleRepository.loadCachedSchedule();
      final studentId = schedule?.term.studentId ?? '';
      if (studentId.isNotEmpty) {
        await AcademicAccountStore().saveStudentId(studentId);
        await _loadAcademicStudentId();
      }
      final summary = await _scheduleRepository.homeSummary();
      unawaited(_scheduleWidgetService.syncFromCache());
      await _scheduleNotificationService.syncScheduleReminders();
      if (mounted) {
        setState(() => _scheduleSummaryText = summary.text);
        _showSnack('校园账户已登录，课表已同步');
      }
      return true;
    } on AcademicAuthException {
      await AcademicAuthService().clearAccount();
      if (mounted) {
        setState(() {
          _hasAcademicSession = false;
          _academicStudentId = null;
        });
        _syncOnboardingAccountStatus();
        _showSnack('校园账户登录未完成，请重试');
      }
      return false;
    } on Object {
      if (mounted) _showSnack('课表同步失败，请稍后重试');
      return false;
    } finally {
      if (mounted) setState(() => _syncingAcademicSchedule = false);
      unawaited(_refreshScheduleSummaryQuietly());
    }
  }

  Future<void> _refreshScheduleSummaryQuietly() async {
    if (_loadingScheduleSummary || _syncingAcademicSchedule) return;
    _loadingScheduleSummary = true;
    try {
      final summary = await _scheduleRepository.homeSummary();
      unawaited(_scheduleWidgetService.syncFromCache());
      if (mounted) setState(() => _scheduleSummaryText = summary.text);
    } on Object {
      if (mounted) setState(() => _scheduleSummaryText = '点击同步教务课表');
    } finally {
      _loadingScheduleSummary = false;
    }
  }

  Future<void> _loadAnnouncementSummaryFromCache() async {
    try {
      final summary = await _announcementRepository.homeSummary();
      if (mounted) setState(() => _announcementSummaryText = summary.text);
    } on Object {
      if (mounted) setState(() => _announcementSummaryText = '点击查看通知公告');
    }
  }

  Future<void> _refreshAnnouncementSummaryQuietly() async {
    if (_loadingAnnouncementSummary) return;
    _loadingAnnouncementSummary = true;
    try {
      final items = await _announcementRepository.fetchAnnouncements();
      if (mounted) {
        setState(() => _announcementSummaryText =
            items.isEmpty ? '点击查看通知公告' : items.first.title);
      }
    } on Object {
      if (mounted && _announcementSummaryText == '正在读取通知公告...') {
        setState(() => _announcementSummaryText = '点击查看通知公告');
      }
    } finally {
      _loadingAnnouncementSummary = false;
    }
  }

  Future<void> _openScheduleFromWidget({bool initialLaunch = false}) async {
    if (_openingScheduleFromWidget || !mounted) return;
    _openingScheduleFromWidget = true;
    if (initialLaunch) {
      setState(() => _hideShellForInitialWidgetLaunch = false);
    }
    try {
      await _openAcademicSystem(
        animatePush: !initialLaunch,
        initialState: initialLaunch ? widget.initialScheduleState : null,
        initialDisplayState:
            initialLaunch ? widget.initialScheduleDisplayState : null,
        initialLoadError:
            initialLaunch ? widget.initialScheduleLoadError : null,
      );
    } finally {
      _openingScheduleFromWidget = false;
    }
  }

  Future<void> _openAcademicSystem({
    bool animatePush = true,
    AcademicScheduleCacheState? initialState,
    AcademicScheduleDisplayState? initialDisplayState,
    String? initialLoadError,
  }) async {
    await Navigator.of(context).push<void>(
      shuyoRoute(
        animatePush: animatePush,
        builder: (_) => AcademicSchedulePage(
          repository: _scheduleRepository,
          notificationService: _scheduleNotificationService,
          widgetService: _scheduleWidgetService,
          onLoginRequired: _handleInvalidAcademicSession,
          initialState: initialState,
          initialDisplayState: initialDisplayState,
          initialLoadError: initialLoadError,
        ),
      ),
    );
    if (mounted) {
      unawaited(_refreshScheduleSummaryQuietly());
      unawaited(_scheduleNotificationService.syncScheduleReminders());
    }
  }

  Future<void> _handleInvalidAcademicSession() async {
    await AcademicAuthService().clearAccount();
    if (!mounted) return;
    setState(() {
      _hasAcademicSession = false;
      _academicStudentId = null;
    });
    _syncOnboardingAccountStatus();
    _showSnack('校园账户登录已失效，请重新登录');
    await _openAcademicLogin();
  }

  Future<void> _openAcademicLogin() async {
    if (widget.isDemo) return;
    final result = await Navigator.of(context).push<NativeLoginResult>(
      shuyoRoute(builder: (_) => const NativeLoginPage()),
    );
    if (result == NativeLoginResult.authenticated && mounted) {
      await _finishAcademicLogin();
    }
  }

  Future<void> _openAnnouncements() async {
    await Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (_) => AnnouncementsPage(repository: _announcementRepository),
      ),
    );
    if (mounted) unawaited(_refreshAnnouncementSummaryQuietly());
  }

  Future<void> _openEmptyClassroom() async {
    await Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (_) => EmptyClassroomPage(
          repository: _classroomRepository,
          initialDate: widget.isDemo ? DateTime(2026, 9, 1) : null,
          onWebVpnExpired: widget.isDemo ? null : _handleWebVpnExpired,
        ),
      ),
    );
  }

  Future<void> _openCourseRatings() async {
    await Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (_) => CourseRatingPage(repository: _courseRatingRepository),
      ),
    );
  }

  Future<void> _openClientSettings() async {
    final hasWebVpnSession = !widget.isDemo &&
        (_webVpnEnabled || await WebVpnSessionStore().hasStoredSession());
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      shuyoRoute(
        builder: (_) => ClientSettingsPage(
          settingsService: _clientSettingsService,
          scheduleNotificationService: _scheduleNotificationService,
          backendRepository: _clientBackendRepository,
          selectedThemeId: widget.selectedThemeId,
          followSystemTheme: widget.followSystemTheme,
          onThemeChanged: widget.onThemeChanged,
          onFollowSystemThemeChanged: widget.onFollowSystemThemeChanged,
          hasAcademicAccount: _hasAcademicSession,
          hasWebVpnSession: hasWebVpnSession,
          onAcademicLogout: _logoutAcademicAccount,
          onWebVpnLogout: _logoutWebVpnSession,
          isDemo: widget.isDemo,
          onExitDemo: widget.onExitDemo,
        ),
      ),
    );
  }

  Future<bool> _logoutAcademicAccount() async {
    try {
      await AcademicAuthService().clearAccount();
      if (!mounted) return false;
      setState(() {
        _hasAcademicSession = false;
        _academicStudentId = null;
      });
      _syncOnboardingAccountStatus();
      return true;
    } on Object {
      _showSnack('校园账户退出失败');
      return false;
    }
  }

  Future<bool> _logoutWebVpnSession() async {
    try {
      await WebVpnSessionStore().clearSession();
      await _setWebVpnEnabled(false);
      return true;
    } on Object {
      _showSnack('WebVPN退出失败');
      return false;
    }
  }

  Future<void> _handleWebVpnExpired() async {
    if (!mounted) return;
    await WebVpnSessionStore().clearSession();
    await _setWebVpnEnabled(false);
    _showSnack('WebVPN已失效，需要重新登录');
  }

  Future<void> _setWebVpnEnabled(bool enabled) async {
    final settings = await _clientSettingsService.loadNetworkSettings();
    if (settings.webVpnEnabled != enabled) {
      await _clientSettingsService.saveNetworkSettings(
        settings.copyWith(webVpnEnabled: enabled),
      );
    }
    final changed = ClassroomUrlResolver.usesWebVpn != enabled;
    ClassroomUrlResolver.configure(useWebVpn: enabled);
    if (changed) _classroomRepository = ClassroomRepository();
    if (mounted) {
      setState(() => _webVpnEnabled = enabled);
      _syncOnboardingAccountStatus();
    }
  }

  Future<bool> _changeWebVpnFromAccountManager(bool enabled) async {
    if (widget.isDemo || !mounted) return false;
    if (enabled) {
      final status = await AcademicAuthService().validateWebVpnSession();
      if (!mounted) return false;
      if (status == WebVpnSessionStatus.unavailable) {
        _showSnack('暂时无法验证WebVPN连接，请稍后重试');
        return false;
      }
      if (status == WebVpnSessionStatus.loginRequired) {
        await WebVpnSessionStore().clearSession();
        if (!mounted) return false;
        final result = await Navigator.of(context).push<NativeLoginResult>(
          shuyoRoute(builder: (_) => const NativeLoginPage.webVpn()),
        );
        if (result != NativeLoginResult.authenticated || !mounted) return false;
      }
    }
    try {
      await _setWebVpnEnabled(enabled);
      return true;
    } on Object {
      _showSnack('WebVPN设置失败，请稍后重试');
      return false;
    }
  }

  Future<void> _checkClientBackendPrompts() async {
    if (widget.isDemo || _checkingClientBackendPrompts) return;
    _checkingClientBackendPrompts = true;
    _lastWebVpnStatusFetchAttempt = DateTime.now();
    try {
      final bootstrap =
          await _clientBackendRepository.fetchBootstrap(forceRefresh: true);
      if (!mounted) return;
      setState(() => _webVpnServiceStatus = bootstrap.webVpnStatus);
      _syncOnboardingAccountStatus();
      if (ClientUpdatePolicy.source == ClientUpdateSource.backend) {
        final version = bootstrap.version;
        if (version.isNewerThan(ClientAppInfo.buildNumber)) {
          final prompt = await _clientBackendRepository
              .shouldPromptUpdate(version.latestBuild);
          if (mounted && prompt) {
            final open = await showClientUpdatePrompt(context, update: version);
            await _clientBackendRepository
                .markUpdatePrompted(version.latestBuild);
            if (open == true && version.hasDownloadUrl && mounted) {
              await _openUpdateDownload(version.downloadUrl);
            }
            return;
          }
        } else {
          await _clientBackendRepository
              .ensureUpdateBaselineInitialized(version.latestBuild);
        }
      }
      final announcement = bootstrap.latestAnnouncement;
      if (announcement == null) {
        await _clientBackendRepository.ensureAnnouncementBaselineInitialized();
        return;
      }
      final prompt = await _clientBackendRepository
          .shouldPromptAnnouncement(announcement.id);
      if (!mounted || !prompt) return;
      final acknowledged = await showInfoConfirmDialog(
        context,
        title: announcement.title,
        message: announcement.content,
        confirmText: '知道了',
        secondaryText: '不再提示',
      );
      if (!acknowledged) {
        await _clientBackendRepository
            .markAnnouncementPrompted(announcement.id);
      }
    } on Object {
      // A backend outage must not block the app.
    } finally {
      _checkingClientBackendPrompts = false;
    }
  }

  Future<void> _refreshWebVpnStatus() async {
    if (widget.isDemo ||
        _refreshingWebVpnStatus ||
        _checkingClientBackendPrompts) {
      return;
    }
    _refreshingWebVpnStatus = true;
    _lastWebVpnStatusFetchAttempt = DateTime.now();
    try {
      final bootstrap =
          await _clientBackendRepository.fetchBootstrap(forceRefresh: true);
      if (mounted) {
        setState(() => _webVpnServiceStatus = bootstrap.webVpnStatus);
        _syncOnboardingAccountStatus();
      }
    } on Object {
      if (mounted && !_webVpnServiceStatus.isFreshAt(DateTime.now())) {
        setState(
          () => _webVpnServiceStatus = const WebVpnServiceStatus.unknown(),
        );
        _syncOnboardingAccountStatus();
      }
    } finally {
      _refreshingWebVpnStatus = false;
    }
  }

  Future<void> _openUpdateDownload(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) {
      _showSnack('下载链接无效');
      return;
    }
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('无法打开下载链接');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
