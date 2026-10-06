import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/services/academic_account_store.dart';
import '../../data/services/library_booking_cache.dart';
import '../../data/services/there_booking_client.dart';
import '../../data/services/unified_account_service.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/empty_state.dart';
import '../auth/native_login_page.dart';
import 'library_booking_resources.dart';

enum _BookingStep {
  venue,
  area,
  viewVenues,
  allAreas,
  date,
  time,
  seat,
  bookingVenues,
  bookings,
}

class LibraryBookingPage extends StatefulWidget {
  const LibraryBookingPage({
    super.key,
    required this.accountService,
    this.client,
    this.useWebVpn = false,
    this.onWebVpnSessionRequired,
    this.schoolClock,
  });

  final UnifiedAccountService accountService;
  final ThereBookingClient? client;
  final bool useWebVpn;
  final Future<bool> Function()? onWebVpnSessionRequired;

  /// Shanghai wall-clock time, overridable for deterministic time selection.
  final DateTime Function()? schoolClock;

  @override
  State<LibraryBookingPage> createState() => _LibraryBookingPageState();
}

class _LibraryBookingPageState extends State<LibraryBookingPage> {
  static const double _timeDigitFontSize = 22;

  late final ThereBookingClient _client =
      widget.client ?? ThereBookingClient(useWebVpn: widget.useWebVpn);
  _BookingStep _step = _BookingStep.venue;
  bool _slideForward = true;
  BookingVenue _venue = BookingVenue.library;
  BookingVenue? _sessionVenue;
  bool _viewOnly = false;
  final Set<BookingVenue> _viewVenueSelection = {};
  final Set<BookingVenue> _bookingVenueSelection = {};
  bool _bookingSelectionReady = false;
  static const _bookingVenuePreference = 'library_booking_selected_venues';
  String _day = ThereBookingClient.schoolDay();
  List<String> _days = [];
  List<Map<String, dynamic>> _areas = [];
  final Map<BookingVenue, List<Map<String, dynamic>>> _allAreasByVenue = {};
  bool _loadingAllAreas = false;
  String? _allAreasError;
  Map<String, dynamic>? _selectedArea;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _areaData;
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _recent = [];
  final LibraryBookingCache _bookingCache = LibraryBookingCache();
  List<Map<String, dynamic>> _homeRecent = [];
  bool _homeCacheLoaded = false;
  String? _cacheStudentId;
  int _cacheGeneration = 0;
  final Map<String, bool> _awaitingWriteStatus = {};
  String _start = '08:30';
  String _end = '09:30';
  int _effectiveMinMinutes = 1;

  DateTime get _schoolNow =>
      widget.schoolClock?.call() ??
      DateTime.now().toUtc().add(const Duration(hours: 8));

  String get _clockDay {
    final now = _schoolNow;
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  int? _previewAvailable;
  bool _previewLoading = false;
  String? _previewError;
  String? _previewKey;
  String _seatFilter = '';
  bool _onlyAvailable = false;
  String? _selectedRoomId;
  String? _error;
  String _loadingLabel = '';
  bool _loading = false;
  bool _loadingSeats = false;
  bool _busy = false;
  int _generation = 0;
  String _bookingFilter = '全部';

  @override
  void initState() {
    super.initState();
    unawaited(_restoreBookingVenues());
    unawaited(_loadHomeCache());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  void _setStep(_BookingStep step, {bool forward = false}) {
    ++_generation;
    setState(() {
      _slideForward = forward;
      _step = step;
      _loading = false;
      _loadingSeats = false;
      _loadingAllAreas = false;
      _error = null;
    });
  }

  void _goBack() {
    if (_busy) return;
    switch (_step) {
      case _BookingStep.venue:
        Navigator.of(context).maybePop();
      case _BookingStep.area:
        _setStep(_BookingStep.venue);
      case _BookingStep.viewVenues:
        _viewOnly = false;
        _setStep(_BookingStep.venue);
      case _BookingStep.allAreas:
        _setStep(_BookingStep.viewVenues);
      case _BookingStep.date:
        _setStep(_viewOnly ? _BookingStep.allAreas : _BookingStep.area);
      case _BookingStep.time:
        _setStep(_BookingStep.date);
      case _BookingStep.seat:
        _setStep(_BookingStep.time);
      case _BookingStep.bookingVenues:
        _setStep(_BookingStep.venue);
      case _BookingStep.bookings:
        _setStep(_BookingStep.bookingVenues);
    }
  }

  @override
  Widget build(BuildContext context) {
    final seatStep = _step == _BookingStep.seat;
    final enteringStep = _step;
    final slideForward = _slideForward;
    return PopScope(
      canPop: _step == _BookingStep.venue && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: ClipRect(
          child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(enteringStep);
          final begin = incoming
              ? Offset(slideForward ? 1 : -1, 0)
              : Offset(slideForward ? -1 : 1, 0);
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero)
                .animate(animation),
            child: child,
          );
        },
        child: ShuYoRouteSurface(
          key: ValueKey(_step),
          child: Scaffold(
            appBar: AppBar(
              leading: _step == _BookingStep.venue
                  ? null
                  : IconButton(
                      tooltip: '返回上一步',
                      onPressed: _busy ? null : _goBack,
                      icon: const Icon(Icons.arrow_back),
                    ),
              title: Text(_pageTitle),
              actions: [
                if (_step != _BookingStep.venue)
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _busy ||
                            _loading ||
                            _loadingSeats ||
                            _loadingAllAreas ||
                            _previewLoading
                        ? null
                        : _retry,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            body: _loading
                ? _loadingBody()
                : _error != null
                    ? EmptyState(
                        icon: _error!.contains('校园网')
                            ? Icons.wifi_off_outlined
                            : Icons.event_busy_outlined,
                        title: '加载失败',
                        message: _error!,
                        action: TextButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      )
                    : _stepBody(),
            bottomNavigationBar: seatStep && !_loading && _error == null
                ? _seatBottomBar()
                : null,
          ),
        ),
      )),
    );
  }

  String get _pageTitle => switch (_step) {
        _BookingStep.venue => '图书馆预约',
        _BookingStep.area => _venue.label,
        _BookingStep.viewVenues => '选择场馆',
        _BookingStep.allAreas => '查看座位情况',
        _BookingStep.date => '选择日期',
        _BookingStep.time => '选择时间',
        _BookingStep.seat => _viewOnly ? '查看座位情况' : '选择座位',
        _BookingStep.bookingVenues => '选择场馆',
        _BookingStep.bookings => '我的预约',
      };

  Widget _loadingBody() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(_loadingLabel, textAlign: TextAlign.center),
          ],
        ),
      );

  Widget _stepBody() => switch (_step) {
        _BookingStep.venue => _venuePage(),
        _BookingStep.area => _areaPage(),
        _BookingStep.viewVenues => _venueSelectionPage(viewOnly: true),
        _BookingStep.allAreas => _allAreasPage(),
        _BookingStep.date => _datePage(),
        _BookingStep.time => _timePage(),
        _BookingStep.seat => _seatPage(),
        _BookingStep.bookingVenues => _venueSelectionPage(viewOnly: false),
        _BookingStep.bookings => _bookingsPage(),
      };

  Widget _surface({required Widget child, EdgeInsetsGeometry? padding}) {
    final colors = context.shuyoColors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: child,
      ),
    );
  }

  Widget _pageList(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      );

  Widget _infoLink(String label, VoidCallback onTap,
          {IconData icon = Icons.help_outline}) =>
      Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16, color: context.shuyoColors.accent),
              const SizedBox(width: 3),
              Text(label,
                  style: TextStyle(
                    color: context.shuyoColors.accent,
                    fontSize: 14.5,
                    height: 1.25,
                    fontWeight: FontWeight.w400,
                  )),
            ]),
          ),
        ),
      );

  void _openInfo(String title, String asset) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ShuYoRouteSurface(
        child: LibraryBookingInfoPage(title: title, asset: asset),
      ),
    ));
  }

  void _showSeatsMap() =>
      unawaited(showLibraryBookingImage(context, librarySeatsAsset));

  Widget _venuePage() => _pageList([
        Row(children: [
          Expanded(
              child:
                  Text('选择场馆', style: Theme.of(context).textTheme.titleLarge)),
          _infoLink('使用规则', () => _openInfo('使用规则', libraryRulesAsset)),
        ]),
        const SizedBox(height: 16),
        for (final venue in BookingVenue.values) ...[
          _surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text(venue.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() => _venue = venue);
                unawaited(_loadVenue());
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () {
            _viewOnly = true;
            _setStep(_BookingStep.viewVenues, forward: true);
          },
          child: const Text('仅查看座位情况'),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _openBookings,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 16, 12),
            child: Row(children: [
              Expanded(
                  child: Text('我的预约',
                      style: Theme.of(context).textTheme.titleLarge)),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _homeRecentSection(),
      ]);

  Widget _homeRecentSection() {
    final colors = context.shuyoColors;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!_homeCacheLoaded)
        const SizedBox(
            height: 64,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
      else if (_homeRecent.isEmpty)
        SizedBox(
            height: 64,
            child: Center(
                child: Text('暂无本地记录',
                    style: TextStyle(color: colors.textTertiary))))
      else
        _surface(
            child: Column(children: [
          for (var index = 0;
              index < _homeRecent.length && index < 3;
              index++) ...[
            if (index > 0) Divider(color: colors.border, height: 20),
            Row(children: [
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      '${_homeRecent[index]['roomName'] ?? '座位'} · '
                      '${_homeRecent[index]['officeAreaName'] ?? ''}',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                      '${_bookingTime(_homeRecent[index]['beginTime'])} — '
                      '${_bookingTime(_homeRecent[index]['endTime'])}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              )),
              const SizedBox(width: 10),
              Text(_bookingCategory(_homeRecent[index]),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.textSecondary)),
            ]),
          ],
        ])),
    ]);
  }

  Future<void> _loadHomeCache() async {
    final generation = ++_cacheGeneration;
    try {
      final studentId = await AcademicAccountStore().loadStudentId();
      final records = studentId == null
          ? <Map<String, dynamic>>[]
          : await _bookingCache.load(studentId);
      if (!mounted || generation != _cacheGeneration) return;
      setState(() {
        _cacheStudentId = studentId;
        _homeRecent = records;
        _homeCacheLoaded = true;
      });
    } on Object {
      if (mounted && generation == _cacheGeneration) {
        setState(() => _homeCacheLoaded = true);
      }
    }
  }

  Future<void> _cacheRecentForVenue(
      BookingVenue venue, List<Map<String, dynamic>> recent) async {
    final generation = ++_cacheGeneration;
    try {
      final studentId = await AcademicAccountStore().loadStudentId();
      if (studentId == null) return;
      final confirmed = <Map<String, dynamic>>[];
      for (final item in recent) {
        final id = ThereBookingClient.string(item['id']);
        final expectsFinish = id == null ? null : _awaitingWriteStatus[id];
        if (expectsFinish != null) {
          final accepted = expectsFinish
              ? _finishedEarly(item)
              : (ThereBookingClient.string(item['status']) == 'CANCEL' ||
                  (ThereBookingClient.string(item['statusLabel']) ?? '')
                      .contains('取消'));
          if (!accepted) continue;
          _awaitingWriteStatus.remove(id);
        }
        confirmed.add(item);
      }
      await _bookingCache.replaceVenue(studentId, venue.roomType, confirmed);
      if (!mounted) return;
      final records = await _bookingCache.load(studentId);
      if (!mounted || generation != _cacheGeneration) return;
      setState(() {
        _cacheStudentId = studentId;
        _homeRecent = records;
        _homeCacheLoaded = true;
      });
    } on Object {
      // Cache failures must not affect an otherwise successful server read.
    }
  }

  Future<void> _removeBookingFromCache(String bookingId) async {
    final generation = ++_cacheGeneration;
    try {
      final studentId =
          _cacheStudentId ?? await AcademicAccountStore().loadStudentId();
      if (studentId == null) return;
      await _bookingCache.removeBooking(studentId, bookingId);
      if (!mounted) return;
      final records = await _bookingCache.load(studentId);
      if (mounted && generation == _cacheGeneration) {
        setState(() => _homeRecent = records);
      }
    } on Object {
      if (mounted) {
        setState(
            () => _homeRecent.removeWhere((item) => item['id'] == bookingId));
      }
    }
  }

  Widget _venueSelectionPage({required bool viewOnly}) {
    final selected = viewOnly ? _viewVenueSelection : _bookingVenueSelection;
    return _pageList([
      Text(viewOnly ? '选择要查看的场馆' : '选择要查看预约的场馆',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 16),
      for (final venue in BookingVenue.values) ...[
        _surface(
          padding: EdgeInsets.zero,
          child: CheckboxListTile(
            key: ValueKey('${viewOnly ? 'view' : 'booking'}-${venue.name}'),
            title: Text(venue.label),
            value: selected.contains(venue),
            controlAffinity: ListTileControlAffinity.trailing,
            onChanged: !viewOnly && !_bookingSelectionReady
                ? null
                : (value) => setState(() {
                      if (value == true) {
                        selected.add(venue);
                      } else {
                        selected.remove(venue);
                      }
                    }),
          ),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 8),
      FilledButton(
        onPressed: selected.isEmpty || (!viewOnly && !_bookingSelectionReady)
            ? null
            : () {
                if (viewOnly) {
                  unawaited(_loadAllAreas());
                } else {
                  unawaited(_saveBookingVenues());
                  setState(() {
                    _slideForward = true;
                    _step = _BookingStep.bookings;
                  });
                  unawaited(_loadBookings());
                }
              },
        child: const Text('下一步'),
      ),
    ]);
  }

  Widget _areaPage() {
    final selectable = _selectableAreas(_areas);
    return _pageList([
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(
            flex: 1,
            child: Text('选择分区',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge)),
        if (_venue == BookingVenue.studySpace)
          Flexible(
              flex: 3,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _infoLink('座位分布', _showSeatsMap, icon: Icons.map_outlined),
                  _infoLink('常见问题', () => _openInfo('常见问题', libraryQaAsset)),
                ]),
              )),
      ]),
      const SizedBox(height: 16),
      if (selectable.isEmpty) const Text('当前场馆没有可选分区'),
      for (final area in selectable) ...[
        _areaCard(_venue, area, _areas),
        const SizedBox(height: 10),
      ],
    ]);
  }

  Widget _allAreasPage() => _pageList([
        if (!_loadingAllAreas &&
            _allAreasByVenue.values
                .every((areas) => _selectableAreas(areas).isEmpty))
          const Text('暂无可查看的分区'),
        for (final venue in BookingVenue.values)
          if (_viewVenueSelection.contains(venue))
            if (_allAreasByVenue[venue]
                case final List<Map<String, dynamic>> areas) ...[
              Text(venue.label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              for (final area in _selectableAreas(areas)) ...[
                _areaCard(venue, area, areas),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 8),
            ],
        if (_loadingAllAreas) ...[
          const SizedBox(height: 10),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 12),
          const Center(child: Text('正在加载其他场馆的分区')),
        ],
        if (_allAreasError != null) Text(_allAreasError!),
      ]);

  List<Map<String, dynamic>> _selectableAreas(
      List<Map<String, dynamic>> areas) {
    final parentIds = areas
        .map((area) => ThereBookingClient.string(area['parentId']))
        .whereType<String>()
        .toSet();
    // Directory nodes can use the same level value as selectable areas.
    final leaves = areas
        .where((area) =>
            !parentIds.contains(ThereBookingClient.string(area['id'])))
        .toList();
    return leaves.isEmpty ? areas : leaves;
  }

  Widget _areaCard(BookingVenue venue, Map<String, dynamic> area,
          List<Map<String, dynamic>> areas) =>
      _surface(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: _step == _BookingStep.allAreas && _loadingAllAreas
              ? null
              : () {
                  setState(() {
                    _slideForward = true;
                    _venue = venue;
                    _areas = areas;
                    _selectedArea = area;
                    _rooms = [];
                    _selectedRoomId = null;
                    _step = _BookingStep.date;
                    _loadingAllAreas = false;
                    _clearPreview();
                  });
                  unawaited(_loadDays());
                },
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                      child: Text(_areaName(area, areas: areas),
                          style: Theme.of(context).textTheme.titleMedium)),
                  const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height: 12),
                Text('开放时间：${_openingHours(area)}'),
                const SizedBox(height: 12),
                _areaStats(area),
              ],
            ),
          ),
        ),
      );

  Widget _areaStats(Map<String, dynamic> area) {
    final open =
        _areaCount(area, 'totalResourceCount', 'disabledResourceCount');
    final busy = _count(area['busyResourceCount']);
    final free = _count(area['freeResourceCount']);
    final base = Theme.of(context).textTheme.bodyMedium;
    final accent = context.shuyoColors.accent;
    final firstLine = '开放座位数 $open / 使用中 $busy';
    final available = TextSpan(style: base, children: [
      const TextSpan(text: '可用 '),
      TextSpan(text: free, style: base?.copyWith(color: accent)),
    ]);
    final fullLine = TextSpan(style: base, children: [
      TextSpan(text: '$firstLine / '),
      available,
    ]);
    return LayoutBuilder(builder: (context, constraints) {
      final painter = TextPainter(
        text: fullLine,
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final fits = painter.width <= constraints.maxWidth;
      if (fits) {
        return Text.rich(fullLine);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(firstLine, style: base),
        const SizedBox(height: 4),
        Text.rich(available),
      ]);
    });
  }

  String _areaName(Map<String, dynamic> area,
      {List<Map<String, dynamic>>? areas}) {
    final parentId = ThereBookingClient.string(area['parentId']);
    final parent =
        (areas ?? _areas).where((item) => item['id'] == parentId).firstOrNull;
    final name = ThereBookingClient.string(area['name']) ?? '未命名分区';
    final parentName = ThereBookingClient.string(parent?['name']);
    return parentName == null ? name : '$parentName - $name';
  }

  String _count(Object? value) => value is num ? value.toInt().toString() : '—';

  String _areaCount(
      Map<String, dynamic> area, String totalKey, String disabledKey) {
    final total = area[totalKey];
    final disabled = area[disabledKey];
    if (total is! num) return '—';
    return (total - (disabled is num ? disabled : 0)).toInt().toString();
  }

  String _openingHours(Map<String, dynamic> area) {
    final rules = ThereBookingClient.object(area['bookingTimes']) ?? const {};
    final start = rules['startHour'];
    final end = rules['endHour'];
    if (start is! num || end is! num) return '以分区规则为准';
    return '${start.toInt().toString().padLeft(2, '0')}:00–${end.toInt().toString().padLeft(2, '0')}:00';
  }

  Widget _datePage() => _pageList([
        Text(_areaName(_selectedArea ?? const {}),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        if (_days.isEmpty) const Text('暂无可选日期，请稍后刷新'),
        for (final day in _days) ...[
          _surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              title: Text(_dateLabel(day)),
              subtitle: Text(_monthDay(day)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                setState(() {
                  _slideForward = true;
                  _day = day;
                  _step = _BookingStep.time;
                  _rooms = [];
                  _selectedRoomId = null;
                  _clearPreview();
                });
                unawaited(_loadAreaRules());
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ]);

  String _dateLabel(String day) {
    final today = ThereBookingClient.schoolDay();
    final todayDate = DateTime.parse(today);
    final tomorrow =
        DateTime.utc(todayDate.year, todayDate.month, todayDate.day + 1);
    final tomorrowText =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    final date = DateTime.tryParse(day);
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final prefix = day == today
        ? '今天'
        : day == tomorrowText
            ? '明天'
            : '';
    return '${prefix.isEmpty ? '' : '$prefix · '}${date == null ? day : weekdays[date.weekday - 1]}';
  }

  String _monthDay(String day) {
    final date = DateTime.tryParse(day);
    return date == null ? day : '${date.month}月${date.day}日';
  }

  Widget _timePage() {
    final rules =
        ThereBookingClient.object(_areaData?['bookingTimes']) ?? const {};
    final choices = _timeChoices(rules);
    final hasInterval = _isValidInterval(_start, _end, rules);
    final colors = context.shuyoColors;
    final max = rules['maxDuration'];
    return _pageList([
      Text('${_dateLabel(_day)} · ${_monthDay(_day)}',
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('${_areaName(_selectedArea ?? const {})}'
          '${max is num ? ' · 最长 ${_durationText(max.toInt())}' : ''}'),
      const SizedBox(height: 18),
      _surface(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text('预约时段',
                    style: Theme.of(context).textTheme.titleMedium)),
            if (hasInterval)
              Text('已选 ${_durationText(_minutes(_end) - _minutes(_start))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      )),
          ]),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
                child: _timePair('开始', _start, choices, rules, start: true)),
            const SizedBox(width: 8),
            const Text('–', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Expanded(
                child: _timePair('结束', _end, choices, rules, start: false)),
          ]),
          if (!hasInterval) ...[
            const SizedBox(height: 18),
            Text(_day == _clockDay ? '今天已无可预约时段，请选择明天' : '当前没有可选时段'),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: Row(children: [
              OutlinedButton.icon(
                onPressed:
                    !hasInterval || _previewLoading ? null : _previewSeats,
                icon: const Icon(Icons.search, size: 18),
                label: Text(_previewLoading ? '查询中…' : '预览可选座位数'),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(
                _previewError ??
                    (_previewAvailable != null &&
                            _previewKey == _currentPreviewKey
                        ? '可选 ${_previewAvailable!} 个'
                        : ''),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color:
                        _previewError == null ? colors.accent : colors.danger),
              )),
            ]),
          ),
        ],
      )),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: !hasInterval || _previewLoading
            ? null
            : () {
                setState(() {
                  _slideForward = true;
                  _step = _BookingStep.seat;
                });
                unawaited(_refreshSeats());
              },
        child: Text(_viewOnly ? '查看座位' : '下一步'),
      ),
    ]);
  }

  Widget _timePair(String label, String value, List<String> choices,
      Map<String, dynamic> rules,
      {required bool start}) {
    final parts = value.split(':');
    final hour = parts.length == 2 ? parts[0] : '—';
    final minute = parts.length == 2 ? parts[1] : '—';
    final enabled = _eligibleTimes(choices, rules, start: start).isNotEmpty;
    return Row(children: [
      Expanded(
          child: _timeBox('$label小时', hour, enabled,
              key: ValueKey(start ? 'start-hour' : 'end-hour'),
              onTap: () => _pickBookingTime(start, true, choices, rules))),
      const Padding(
          padding: EdgeInsets.symmetric(horizontal: 3),
          child: Text(':', style: TextStyle(fontSize: 22))),
      Expanded(
          child: _timeBox('$label分钟', minute, enabled,
              key: ValueKey(start ? 'start-minute' : 'end-minute'),
              onTap: () => _pickBookingTime(start, false, choices, rules))),
    ]);
  }

  Widget _timeBox(String label, String value, bool enabled,
      {required Key key, required VoidCallback onTap}) {
    final colors = context.shuyoColors;
    return Semantics(
      label: label,
      button: true,
      enabled: enabled,
      child: Material(
        color: enabled ? colors.surface : colors.disabledFill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          key: key,
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderStrong),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: _timeDigitFontSize,
                    fontWeight: FontWeight.w500,
                  )),
            ),
          ),
        ),
      ),
    );
  }

  List<String> _eligibleTimes(List<String> choices, Map<String, dynamic> rules,
          {required bool start}) =>
      [
        for (final value in choices)
          if (start
              ? choices.any((end) => _isValidInterval(value, end, rules))
              : choices.any((begin) => _isValidInterval(begin, value, rules)))
            value,
      ];

  Future<void> _pickBookingTime(bool start, bool focusHour,
      List<String> choices, Map<String, dynamic> rules) async {
    final eligible = _eligibleTimes(choices, rules, start: start);
    if (eligible.isEmpty) return;
    final current = start ? _start : _end;
    final initial = eligible.contains(current) ? current : eligible.first;
    var selectedHour = initial.substring(0, 2);
    var selectedMinute = initial.substring(3, 5);
    final hours =
        eligible.map((value) => value.substring(0, 2)).toSet().toList();
    final initialMinutes = eligible
        .where((value) => value.startsWith('$selectedHour:'))
        .map((value) => value.substring(3, 5))
        .toSet()
        .toList();
    final hourController =
        FixedExtentScrollController(initialItem: hours.indexOf(selectedHour));
    final minuteController = FixedExtentScrollController(
        initialItem: initialMinutes.indexOf(selectedMinute));
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.shuyoColors.surface,
      elevation: 0,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, updateSheet) {
          final minutes = eligible
              .where((value) => value.startsWith('$selectedHour:'))
              .map((value) => value.substring(3, 5))
              .toSet()
              .toList();
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(start ? '选择开始时间' : '选择结束时间',
                    style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text('$selectedHour:$selectedMinute',
                    style: Theme.of(sheetContext).textTheme.headlineSmall),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: _timeWheel(
                    sheetContext,
                    '小时',
                    hours,
                    selected: selectedHour,
                    controller: hourController,
                    focused: focusHour,
                    onSelect: (index) {
                      final hour = hours[index];
                      if (hour == selectedHour) return;
                      updateSheet(() {
                        selectedHour = hour;
                        focusHour = true;
                        final available = eligible
                            .where((value) => value.startsWith('$hour:'))
                            .map((value) => value.substring(3, 5))
                            .toSet()
                            .toList();
                        if (!available.contains(selectedMinute)) {
                          selectedMinute = available.first;
                        }
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!minuteController.hasClients) return;
                        final available = eligible
                            .where((value) => value.startsWith('$hour:'))
                            .map((value) => value.substring(3, 5))
                            .toSet()
                            .toList();
                        minuteController
                            .jumpToItem(available.indexOf(selectedMinute));
                      });
                    },
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _timeWheel(
                    sheetContext,
                    '分钟',
                    minutes,
                    selected: selectedMinute,
                    controller: minuteController,
                    focused: !focusHour,
                    onSelect: (index) => updateSheet(() {
                      selectedMinute = minutes[index];
                      focusHour = false;
                    }),
                  )),
                ]),
                const SizedBox(height: 18),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                          sheetContext, '$selectedHour:$selectedMinute'),
                      child: const Text('确认时间'),
                    )),
              ]),
            ),
          );
        },
      ),
    );
    hourController.dispose();
    minuteController.dispose();
    if (picked == null || !mounted || _step != _BookingStep.time) return;
    final index = choices.indexOf(picked);
    if (index >= 0) _applyTimeSelection(start, index, choices, rules);
  }

  Widget _timeWheel(BuildContext context, String title, List<String> options,
      {required String selected,
      required FixedExtentScrollController controller,
      required bool focused,
      required ValueChanged<int> onSelect}) {
    final colors = context.shuyoColors;
    return Column(children: [
      Text(title,
          style:
              TextStyle(color: focused ? colors.accent : colors.textSecondary)),
      const SizedBox(height: 7),
      SizedBox(
          height: 220,
          child: CupertinoPicker(
            key: ValueKey('time-wheel-$title'),
            itemExtent: 44,
            scrollController: controller,
            backgroundColor: colors.surface,
            selectionOverlay: null,
            onSelectedItemChanged: onSelect,
            children: [
              for (final option in options)
                Center(
                    child: Text(option,
                        style: TextStyle(
                          color: option == selected
                              ? colors.accent
                              : colors.textPrimary,
                          fontWeight: option == selected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ))),
            ],
          )),
    ]);
  }

  void _applyTimeSelection(bool start, int requested, List<String> choices,
      Map<String, dynamic> rules) {
    final earliest = _earliestAllowedStart;
    bool valid(String begin, String end) =>
        _validIntervalAt(begin, end, rules, earliest);
    final candidates = <int>[
      for (var i = 0; i < choices.length; i++)
        if (start
            ? choices.any((end) => valid(choices[i], end))
            : choices.any((begin) => valid(begin, choices[i])))
          i,
    ];
    if (candidates.isEmpty) return;
    candidates
        .sort((a, b) => (a - requested).abs().compareTo((b - requested).abs()));
    final chosen = choices[candidates.first];
    final counterparts = choices
        .where((other) => start ? valid(chosen, other) : valid(other, chosen))
        .toList();
    if (counterparts.isEmpty) return;
    final previous = start ? _end : _start;
    counterparts.sort((a, b) => (_minutes(a) - _minutes(previous))
        .abs()
        .compareTo((_minutes(b) - _minutes(previous)).abs()));
    setState(() {
      if (start) {
        _start = chosen;
        _end = counterparts.first;
      } else {
        _end = chosen;
        _start = counterparts.first;
      }
      _clearPreview();
    });
  }

  String get _currentPreviewKey =>
      '${_venue.roomType}|${ThereBookingClient.string(_selectedArea?['id'])}|$_day|$_start|$_end';

  void _clearPreview() {
    _previewAvailable = null;
    _previewError = null;
    _previewKey = null;
    _previewLoading = false;
  }

  Future<void> _previewSeats() async {
    final id = ThereBookingClient.string(_selectedArea?['id']);
    if (id == null || _previewLoading) return;
    final key = _currentPreviewKey;
    final day = _day;
    final start = _start;
    final end = _end;
    final venue = _venue;
    setState(() {
      _previewLoading = true;
      _previewError = null;
      _previewAvailable = null;
    });
    try {
      await _client.selectVenue(venue);
      _sessionVenue = venue;
      final data =
          await _read(() => _client.area(id, '$day $start', '$day $end'));
      if (!mounted || _step != _BookingStep.time || key != _currentPreviewKey) {
        return;
      }
      setState(() {
        _previewAvailable =
            ThereBookingClient.objects(data['rooms']).where(_isBookable).length;
        _previewKey = key;
        _previewLoading = false;
      });
    } on Object catch (error) {
      if (!mounted || _step != _BookingStep.time || key != _currentPreviewKey) {
        return;
      }
      setState(() {
        _previewError = _friendlyError(error);
        _previewLoading = false;
      });
    }
  }

  int _minutes(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return -1;
    return (int.tryParse(parts[0]) ?? -1) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _durationText(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '$rest 分钟';
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }

  bool _isValidInterval(String start, String end, Map<String, dynamic> rules) {
    return _validIntervalAt(start, end, rules, _earliestAllowedStart);
  }

  int get _earliestAllowedStart {
    final now = _schoolNow;
    final today = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    if (_day.compareTo(today) < 0) return 24 * 60 + 1;
    if (_day != today) return 0;
    return now.hour * 60 +
        now.minute +
        (now.second > 0 || now.millisecond > 0 ? 1 : 0);
  }

  bool _validIntervalAt(
      String start, String end, Map<String, dynamic> rules, int earliest) {
    final startMinutes = _minutes(start);
    final duration = _minutes(end) - startMinutes;
    final max = rules['maxDuration'];
    return startMinutes >= earliest &&
        duration >= _effectiveMinMinutes &&
        (max is! num || duration <= max);
  }

  int _minimumStep(List<String> choices) {
    int? result;
    for (var i = 1; i < choices.length; i++) {
      final gap = _minutes(choices[i]) - _minutes(choices[i - 1]);
      if (gap > 0 && (result == null || gap < result)) result = gap;
    }
    return result ?? 1;
  }

  ({String start, String end}) _defaultTimeRange(
      List<String> choices, Map<String, dynamic> rules) {
    final starts = choices
        .where((start) =>
            choices.any((end) => _isValidInterval(start, end, rules)))
        .toList();
    if (starts.isEmpty) return (start: '', end: '');
    final today = _day == _clockDay;
    final start =
        today ? starts.first : starts[((starts.length - 1) / 3).round()];
    final targetDuration = today ? 120 : 180;
    final ends =
        choices.where((end) => _isValidInterval(start, end, rules)).toList();
    if (ends.isEmpty) return (start: '', end: '');
    final withinTarget = ends
        .where((end) => _minutes(end) - _minutes(start) <= targetDuration)
        .toList();
    final end = withinTarget.isNotEmpty ? withinTarget.last : ends.first;
    return (start: start, end: end);
  }

  List<String> _timeChoices(Map<String, dynamic> rules) {
    final firstMinute = ((rules['startHour'] as num?)?.toInt() ?? 0) * 60;
    final lastMinute = ((rules['endHour'] as num?)?.toInt() ?? 24) * 60;
    List<String> bounded(Iterable<String> values) => (values
        .where((value) =>
            _minutes(value) >= firstMinute && _minutes(value) <= lastMinute)
        .toSet()
        .toList()
      ..sort());
    final direct = ThereBookingClient.strings(rules['meetingHalfHours']);
    if (direct.isNotEmpty) {
      final result = {...direct};
      final endHour = rules['endHour'];
      if (endHour is num) {
        result.add('${endHour.toInt().toString().padLeft(2, '0')}:00');
      }
      return bounded(result);
    }
    final blocks = ThereBookingClient.objects(rules['timeBlocks']);
    if (blocks.isNotEmpty) {
      final values = <String>{};
      for (final block in blocks) {
        if (block['disabled'] == true) continue;
        if (ThereBookingClient.string(block['start']) case final String value) {
          values.add(value);
        }
        if (ThereBookingClient.string(block['end']) case final String value) {
          values.add(value);
        }
      }
      return bounded(values);
    }
    final start = (rules['startHour'] as num?)?.toInt() ?? 0;
    final end = (rules['endHour'] as num?)?.toInt() ?? 24;
    final interval = (rules['meetingInterval'] as num?)?.toInt() ?? 30;
    if (interval <= 0) return [];
    return [
      for (var minute = start * 60; minute <= end * 60; minute += interval)
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}',
    ];
  }

  Widget _seatPage() {
    if (_loadingSeats) return _loadingBody();
    final available = _rooms.where(_isBookable).length;
    final visible = _rooms.where((room) {
      final name = ThereBookingClient.string(room['name']) ?? '';
      return (!_onlyAvailable || _isBookable(room)) &&
          name.toLowerCase().contains(_seatFilter.toLowerCase());
    }).toList();
    return CustomScrollView(slivers: [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        sliver: SliverToBoxAdapter(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Text(_areaName(_selectedArea ?? const {}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium)),
              if (_venue == BookingVenue.studySpace)
                _infoLink('座位分布', _showSeatsMap, icon: Icons.map_outlined),
            ]),
            const SizedBox(height: 4),
            Text(
                '${_monthDay(_day)}  $_start–$_end · 可选 $available / ${_rooms.length}'),
            const SizedBox(height: 14),
            TextField(
              decoration: const InputDecoration(
                  hintText: '搜索座位号', prefixIcon: Icon(Icons.search)),
              onChanged: (value) => setState(() => _seatFilter = value.trim()),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('仅看可选座位'),
              value: _onlyAvailable,
              onChanged: (value) => setState(() => _onlyAvailable = value),
            ),
            if (_rooms.isEmpty) const Text('所选时段没有返回座位，请更换时间'),
            if (_rooms.isNotEmpty && visible.isEmpty) const Text('没有符合条件的座位'),
          ],
        )),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final width = constraints.crossAxisExtent - 32;
          final columns = width >= 480 ? 6 : 5;
          return SliverGrid.builder(
            itemCount: visible.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: 7,
              mainAxisSpacing: 7,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final room = visible[index];
              final id = ThereBookingClient.string(room['id']);
              final name = ThereBookingClient.string(room['name']) ?? id ?? '—';
              final enabled = _isBookable(room);
              final selected = id != null && id == _selectedRoomId;
              final colors = context.shuyoColors;
              return Tooltip(
                message: '$name${enabled ? '，可选' : '，不可选'}',
                child: InkWell(
                  onTap: !_viewOnly && enabled && !_busy && id != null
                      ? () =>
                          setState(() => _selectedRoomId = selected ? null : id)
                      : null,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.accent
                          : enabled
                              ? colors.surface
                              : colors.disabledFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: selected ? colors.accent : colors.border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(name,
                            style: TextStyle(
                              color: selected
                                  ? colors.onAccent
                                  : enabled
                                      ? colors.textPrimary
                                      : colors.textMuted,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    ]);
  }

  Widget _seatBottomBar() {
    final room =
        _rooms.where((item) => item['id'] == _selectedRoomId).firstOrNull;
    final colors = context.shuyoColors;
    return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.border)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08), blurRadius: 16)
            ],
          ),
          child: Row(children: [
            Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_viewOnly ? '仅查看座位情况' : '已选座位',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                      _viewOnly
                          ? '${_monthDay(_day)} · $_start–$_end'
                          : '${ThereBookingClient.string(room?['name']) ?? '请选择座位'} · $_start–$_end',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ])),
            if (!_viewOnly)
              FilledButton(
                onPressed: _busy || _loadingSeats || _selectedRoomId == null
                    ? null
                    : _createBooking,
                child: Text(_busy ? '提交中…' : '确认预约'),
              ),
          ]),
        ));
  }

  Widget _bookingsPage() {
    const filters = ['全部', '待履约', '进行中', '已结束', '已取消'];
    final visible = _recent
        .where((item) =>
            _bookingFilter == '全部' || _bookingCategory(item) == _bookingFilter)
        .toList();
    return _pageList([
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final filter in filters)
              SizedBox(
                width: 86,
                child: Semantics(
                  button: true,
                  selected: _bookingFilter == filter,
                  child: Column(children: [
                    InkWell(
                      onTap: () => setState(() => _bookingFilter = filter),
                      child: SizedBox(
                          height: 42,
                          child: Center(
                            child: Text(filter,
                                style: TextStyle(
                                  color: _bookingFilter == filter
                                      ? context.shuyoColors.accent
                                      : context.shuyoColors.textSecondary,
                                  fontWeight: _bookingFilter == filter
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                )),
                          )),
                    ),
                    Container(
                        height: 2,
                        color: _bookingFilter == filter
                            ? context.shuyoColors.accent
                            : Colors.transparent),
                  ]),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (visible.isEmpty) Text(_recent.isEmpty ? '暂无预约记录' : '没有符合条件的预约'),
      for (final item in visible) ...[
        _surface(
            padding: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _openDetail(item),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${ThereBookingClient.string(item['roomName']) ?? '座位'} · '
                          '${ThereBookingClient.string(item['officeAreaName']) ?? _bookingVenueName(item)}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 6),
                      Text(_bookingVenueName(item),
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Text(
                          '${_bookingTime(item['beginTime'])} — '
                          '${_bookingTime(item['endTime'])}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  )),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                        _finishedEarly(item) ? '已提前结束' : _bookingCategory(item),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: context.shuyoColors.textSecondary)),
                  ),
                ]),
              ),
            )),
        const SizedBox(height: 10),
      ],
    ]);
  }

  String _bookingVenueName(Map<String, dynamic> item) =>
      BookingVenue.values
          .where((venue) => venue.roomType == item['roomType'])
          .firstOrNull
          ?.label ??
      '图书馆预约';

  String _bookingCategory(Map<String, dynamic> item) {
    final status =
        (ThereBookingClient.string(item['status']) ?? '').toUpperCase();
    final label = ThereBookingClient.string(item['statusLabel']) ?? '';
    if (_finishedEarly(item)) return '已结束';
    if (status == 'CANCEL' || label.contains('取消')) return '已取消';
    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    DateTime? parse(Object? value) {
      final text = ThereBookingClient.string(value);
      return text == null
          ? null
          : DateTime.tryParse('${text.replaceFirst(' ', 'T')}Z');
    }

    final begin = parse(item['beginTime']);
    final end = parse(item['endTime']);
    if (begin != null && now.isBefore(begin)) return '待履约';
    if (end != null && now.isBefore(end)) return '进行中';
    return '已结束';
  }

  bool _finishedEarly(Map<String, dynamic> item) {
    final original = ThereBookingClient.string(item['origEndAt']);
    final end = ThereBookingClient.string(item['endTime']);
    return original != null &&
        end != null &&
        end.compareTo(original) < 0 &&
        item['duration'] == 0;
  }

  String _bookingStatusText(Map<String, dynamic> item) => _finishedEarly(item)
      ? '已提前结束'
      : ThereBookingClient.string(item['statusLabel']) ??
          _bookingCategory(item);

  void _retry() {
    switch (_step) {
      case _BookingStep.venue:
        break;
      case _BookingStep.area:
        unawaited(_loadVenue());
      case _BookingStep.viewVenues:
        break;
      case _BookingStep.allAreas:
        unawaited(_loadAllAreas());
      case _BookingStep.date:
        unawaited(_loadDays());
      case _BookingStep.time:
        unawaited(_loadAreaRules());
      case _BookingStep.seat:
        unawaited(_refreshSeats());
      case _BookingStep.bookingVenues:
        break;
      case _BookingStep.bookings:
        unawaited(_loadBookings());
    }
  }

  void _openBookings() {
    if (_busy) return;
    setState(() {
      _slideForward = true;
      _step = _BookingStep.bookingVenues;
      _bookingFilter = '全部';
    });
  }

  Future<void> _restoreBookingVenues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_bookingVenuePreference) ?? const [];
      if (!mounted) return;
      setState(() {
        _bookingVenueSelection
          ..clear()
          ..addAll(BookingVenue.values
              .where((venue) => saved.contains(venue.roomType)));
        _bookingSelectionReady = true;
      });
    } on Object {
      if (mounted) setState(() => _bookingSelectionReady = true);
    }
  }

  Future<void> _saveBookingVenues() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_bookingVenuePreference, [
        for (final venue in BookingVenue.values)
          if (_bookingVenueSelection.contains(venue)) venue.roomType,
      ]);
    } on Object {
      // A local preference failure must not block reading bookings.
    }
  }

  Future<void> _loadVenue() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _slideForward = true;
      _step = _BookingStep.area;
      _loading = true;
      _loadingLabel = '正在连接至${_venue.label}';
      _error = null;
      _selectedArea = null;
      _selectedRoomId = null;
      _rooms = [];
    });
    try {
      _profile = await _read<Map<String, dynamic>>(() async {
        await _client.selectVenue(_venue);
        _sessionVenue = _venue;
        return _client.profile();
      }, validateAfterRecovery: _checkAccount);
      await _checkAccount(_profile!);
      final areas =
          await _read(() => _client.areas(ThereBookingClient.schoolDay()));
      if (!mounted || generation != _generation) return;
      setState(() {
        _areas = areas
            .where((area) =>
                ThereBookingClient.strings(area['supportRoomTypes'])
                    .contains(_venue.roomType))
            .toList();
        _loading = false;
      });
      try {
        await widget.accountService.setTherePendingRecovery(false);
      } on Object {
        // The business data is usable even if the local marker fails.
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      try {
        await widget.accountService.setTherePendingRecovery(true);
      } on Object {
        // Keep the service error visible.
      }
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  Future<void> _loadAllAreas() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _slideForward = true;
      _step = _BookingStep.allAreas;
      _viewOnly = true;
      _loading = true;
      _loadingAllAreas = true;
      _loadingLabel = '正在连接至座位预约系统';
      _allAreasError = null;
      _allAreasByVenue.clear();
      _error = null;
    });
    final failures = <String>[];
    var verified = false;
    for (final venue
        in BookingVenue.values.where(_viewVenueSelection.contains)) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadingLabel = '正在连接至${venue.label}');
      try {
        await _read(() async {
          await _client.selectVenue(venue);
          _sessionVenue = venue;
          if (!verified) {
            await _checkAccount(await _client.profile());
            verified = true;
          }
          return true;
        });
        final areas =
            await _read(() => _client.areas(ThereBookingClient.schoolDay()));
        if (!mounted || generation != _generation) return;
        setState(() {
          _allAreasByVenue[venue] = areas
              .where((area) =>
                  ThereBookingClient.strings(area['supportRoomTypes'])
                      .contains(venue.roomType))
              .toList();
          _loading = false;
        });
      } on Object catch (error) {
        failures.add('${venue.label}：${_friendlyError(error)}');
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      _loadingAllAreas = false;
      if (_allAreasByVenue.isEmpty) {
        _error = failures.firstOrNull ?? '暂时无法加载分区';
      } else if (failures.isNotEmpty) {
        _allAreasError = '部分场馆暂时无法加载，可点击右上角刷新';
      }
    });
  }

  Future<void> _loadDays() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingLabel = '正在加载可预约日期';
      _error = null;
    });
    try {
      await _client.selectVenue(_venue);
      _sessionVenue = _venue;
      final overview =
          await _read(() => _client.overview(ThereBookingClient.schoolDay()));
      if (!mounted || generation != _generation) return;
      setState(() {
        _days = _bookingDays(overview);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadAreaRules() async {
    final id = ThereBookingClient.string(_selectedArea?['id']);
    if (id == null) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingLabel = '正在加载分区开放时间';
      _error = null;
      _clearPreview();
    });
    try {
      await _client.selectVenue(_venue);
      _sessionVenue = _venue;
      final data = await _read(() => _client.area(id, _day, _day));
      if (!mounted || generation != _generation) return;
      final rules = ThereBookingClient.object(data['bookingTimes']) ?? const {};
      final choices = _timeChoices(rules);
      final explicitMin = rules['minDuration'];
      _effectiveMinMinutes = explicitMin is num && explicitMin > 0
          ? explicitMin.toInt()
          : _minimumStep(choices);
      final defaults = _defaultTimeRange(choices, rules);
      setState(() {
        _areaData = data;
        _start = defaults.start;
        _end = defaults.end;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _refreshSeats() async {
    final id = ThereBookingClient.string(_selectedArea?['id']);
    if (id == null || !mounted || _step != _BookingStep.seat) return;
    final generation = ++_generation;
    setState(() {
      _loadingSeats = true;
      _loadingLabel = '正在加载分区座位情况';
      _selectedRoomId = null;
    });
    try {
      await _client.selectVenue(_venue);
      _sessionVenue = _venue;
      final result =
          await _read(() => _client.area(id, '$_day $_start', '$_day $_end'));
      if (!mounted || generation != _generation) return;
      setState(() {
        _areaData = result;
        _rooms = ThereBookingClient.objects(result['rooms']);
        _loadingSeats = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loadingSeats = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<void> _loadBookings() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _loadingLabel = '正在连接至座位预约系统';
      _error = null;
    });
    try {
      final byId = <String, Map<String, dynamic>>{};
      var verified = false;
      for (final venue
          in BookingVenue.values.where(_bookingVenueSelection.contains)) {
        if (!mounted || generation != _generation) return;
        setState(() => _loadingLabel = '正在读取${venue.label}的预约');
        await _read(() async {
          await _client.selectVenue(venue);
          _sessionVenue = venue;
          if (!verified) {
            await _checkAccount(await _client.profile());
            verified = true;
          }
          return true;
        });
        final recent = await _read(_client.recent);
        await _cacheRecentForVenue(venue, recent);
        for (final item in recent) {
          final id = ThereBookingClient.string(item['id']);
          if (id != null &&
              !_awaitingWriteStatus.containsKey(id) &&
              _bookingVenueSelection
                  .any((selected) => selected.roomType == item['roomType'])) {
            byId[id] = item;
          }
        }
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _recent = byId.values.toList()
          ..sort((a, b) => (ThereBookingClient.string(b['beginTime']) ?? '')
              .compareTo(ThereBookingClient.string(a['beginTime']) ?? ''));
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(error);
      });
    }
  }

  Future<bool> _authenticate() async {
    await _client.prepareOAuth();
    final callback = await widget.accountService.authorizeThere();
    if (callback != null) {
      await _client.completeOAuth(callback);
      return true;
    }
    if (widget.useWebVpn) {
      throw const ThereBookingException(
        ThereFailureKind.loginRequired,
        '统一认证会话已失效，请先在账号管理恢复WebVPN登录后重试',
      );
    }
    if (!mounted) return false;
    final result = await Navigator.of(context).push<NativeLoginResult>(
      MaterialPageRoute(
        builder: (_) => const ShuYoRouteSurface(
          child: NativeLoginPage.there(),
        ),
      ),
    );
    if (result == NativeLoginResult.authenticated) {
      _client.resetSession();
      return true;
    }
    return false;
  }

  Future<T> _read<T>(
    Future<T> Function() operation, {
    Future<void> Function(T)? validateAfterRecovery,
  }) async {
    try {
      return await operation();
    } on ThereBookingException catch (error) {
      if (error.kind == ThereFailureKind.webVpnLoginRequired &&
          widget.useWebVpn) {
        final restored = await widget.onWebVpnSessionRequired?.call() ?? false;
        if (!restored) rethrow;
        _client.resetSession();
        return _readAfterRecovery(operation, validateAfterRecovery);
      }
      if (error.kind != ThereFailureKind.loginRequired) rethrow;
    }
    final authenticated = await _authenticate();
    if (!authenticated) {
      throw const ThereBookingException(
        ThereFailureKind.loginRequired,
        '请先登录图书馆预约',
      );
    }
    return _readAfterRecovery(operation, validateAfterRecovery);
  }

  Future<T> _readAfterRecovery<T>(
    Future<T> Function() operation,
    Future<void> Function(T)? validateAfterRecovery,
  ) async {
    await _client.selectVenue(_sessionVenue ?? _venue);
    if (validateAfterRecovery != null) {
      final result = await operation();
      await validateAfterRecovery(result);
      return result;
    }
    await _checkAccount(await _client.profile());
    return operation();
  }

  Future<void> _checkAccount(Map<String, dynamic> profile) async {
    final expected = await AcademicAccountStore().loadStudentId();
    if (expected != null &&
        !ThereBookingClient.matchesAccount(profile, expected)) {
      await _client.clearSession();
      throw const ThereBookingException(
        ThereFailureKind.business,
        '图书馆预约登录的是另一个校园账户，请退出校园账户后重新登录',
      );
    }
  }

  Future<void> _createBooking() async {
    final areaId = ThereBookingClient.string(_selectedArea?['id']);
    final roomId = _selectedRoomId;
    if (_busy || areaId == null || roomId == null) return;
    final room = _rooms.where((item) => item['id'] == roomId).firstOrNull;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认预约'),
            content: Text('${_venue.label}\n'
                '${ThereBookingClient.string(_selectedArea?['name']) ?? ''} · '
                '${ThereBookingClient.string(room?['name']) ?? '座位'}\n'
                '$_day  $_start—$_end'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('提交'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    String? createdId;
    try {
      await _client.selectVenue(_venue);
      _sessionVenue = _venue;
      createdId = await _client.create(
        areaId: areaId,
        roomId: roomId,
        day: _day,
        start: _start,
        end: _end,
      );
    } on ThereBookingException catch (error) {
      if (error.kind == ThereFailureKind.uncertain) {
        try {
          final recent = await _read(_client.recent);
          if (mounted) {
            setState(() => _recent = recent);
            await _cacheRecentForVenue(_venue, recent);
          }
        } on Object {
          // Keep the uncertain result; a new create request is not automatic.
        }
      }
      if (error.kind == ThereFailureKind.loginRequired ||
          error.kind == ThereFailureKind.webVpnLoginRequired) {
        await _recoverAfterWrite(
          webVpn: error.kind == ThereFailureKind.webVpnLoginRequired,
        );
        return;
      }
      if (mounted) _showMessage(error.message);
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (createdId == null || !mounted) return;
    _showMessage('预约已创建，正在核对服务端记录');
    try {
      final recent = await _read(_client.recent);
      if (!mounted) return;
      setState(() => _recent = recent);
      await _cacheRecentForVenue(_venue, recent);
      await _refreshSeats();
      if (mounted) await _openDetail({'id': createdId});
    } on Object {
      if (mounted) _showMessage('预约已创建，但最新记录暂时无法加载，请稍后刷新');
    }
  }

  Future<void> _openDetail(Map<String, dynamic> booking) async {
    final id = ThereBookingClient.string(booking['id']);
    if (id == null) return;
    try {
      final venue = BookingVenue.values
              .where((item) => item.roomType == booking['roomType'])
              .firstOrNull ??
          _venue;
      final detail = await _read(() async {
        await _client.selectVenue(venue);
        _sessionVenue = venue;
        return _client.detail(id);
      });
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width),
        builder: (sheetContext) => SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85),
            decoration: BoxDecoration(
              color: sheetContext.shuyoColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                        child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: sheetContext.shuyoColors.borderStrong,
                          borderRadius: BorderRadius.circular(4)),
                    )),
                    const SizedBox(height: 20),
                    Text(
                        ThereBookingClient.string(detail['roomName']) ?? '预约详情',
                        style: Theme.of(sheetContext).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Row(children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: sheetContext.shuyoColors.accent,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 7),
                      Text(_bookingStatusText(detail),
                          style: Theme.of(sheetContext)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: sheetContext.shuyoColors.accent)),
                    ]),
                    const SizedBox(height: 18),
                    Divider(color: sheetContext.shuyoColors.border),
                    const SizedBox(height: 12),
                    _bookingDetailField(sheetContext, '场馆', venue.label),
                    _bookingDetailField(
                        sheetContext,
                        '分区',
                        ThereBookingClient.string(
                                detail['allOfficeAreaName']) ??
                            ThereBookingClient.string(
                                booking['allOfficeAreaName']) ??
                            ThereBookingClient.string(
                                booking['officeAreaName']) ??
                            ''),
                    _bookingDetailField(sheetContext, '座位',
                        ThereBookingClient.string(detail['roomName']) ?? ''),
                    _bookingDetailField(sheetContext, '开始时间',
                        _bookingTime(detail['beginTime'])),
                    _bookingDetailField(
                        sheetContext, '结束时间', _bookingTime(detail['endTime'])),
                    if (ThereBookingClient.strings(detail['abilities'])
                        .contains('cancel')) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_cancelBooking(id));
                            },
                            icon: const Icon(Icons.event_busy_outlined),
                            label: const Text('取消预约'),
                          )),
                    ],
                    if (ThereBookingClient.strings(detail['abilities'])
                        .contains('close')) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(sheetContext);
                              unawaited(_finishBooking(id));
                            },
                            icon: const Icon(Icons.stop_circle_outlined),
                            label: const Text('提前结束'),
                          )),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  Widget _bookingDetailField(BuildContext context, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
            width: 96,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: context.shuyoColors.textSecondary))),
        Expanded(child: Text(value)),
      ]),
    );
  }

  Future<void> _cancelBooking(String id) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('取消这条预约'),
            content: const Text('取消后需重新预约'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    var cancelled = false;
    try {
      await _client.cancel(id);
      cancelled = true;
    } on ThereBookingException catch (error) {
      if (error.kind == ThereFailureKind.loginRequired ||
          error.kind == ThereFailureKind.webVpnLoginRequired) {
        await _recoverAfterWrite(
          webVpn: error.kind == ThereFailureKind.webVpnLoginRequired,
        );
      } else if (mounted) {
        _showMessage(error.message);
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!cancelled || !mounted) return;
    _showMessage('已取消预约');
    _awaitingWriteStatus[id] = false;
    await _removeBookingFromCache(id);
    try {
      if (_step == _BookingStep.bookings) {
        await _loadBookings();
      } else {
        final recent = await _read(_client.recent);
        if (!mounted) return;
        setState(() => _recent = recent);
        await _cacheRecentForVenue(_sessionVenue ?? _venue, recent);
        await _refreshSeats();
      }
    } on Object {
      if (mounted) _showMessage('已取消预约，列表暂时无法刷新');
    }
  }

  Future<void> _finishBooking(String id) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('提前结束'),
            content: const Text('结束后将无法取消'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    var finished = false;
    try {
      await _client.finish(id);
      finished = true;
    } on ThereBookingException catch (error) {
      if (error.kind == ThereFailureKind.loginRequired ||
          error.kind == ThereFailureKind.webVpnLoginRequired) {
        await _recoverAfterWrite(
          webVpn: error.kind == ThereFailureKind.webVpnLoginRequired,
        );
      } else if (mounted) {
        _showMessage(error.message);
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!finished || !mounted) return;
    _showMessage('已提交提前结束，正在读取最终状态');
    _awaitingWriteStatus[id] = true;
    await _removeBookingFromCache(id);
    try {
      if (_step == _BookingStep.bookings) {
        await _loadBookings();
      } else {
        final recent = await _read(_client.recent);
        if (!mounted) return;
        setState(() => _recent = recent);
        await _cacheRecentForVenue(_sessionVenue ?? _venue, recent);
        await _refreshSeats();
      }
    } on Object {
      if (mounted) _showMessage('操作已提交，列表暂时无法刷新');
    }
  }

  Future<void> _recoverAfterWrite({bool webVpn = false}) async {
    try {
      final recovered = webVpn
          ? await widget.onWebVpnSessionRequired?.call() ?? false
          : await _authenticate();
      if (!recovered || !mounted) return;
      if (webVpn) _client.resetSession();
      if (_step == _BookingStep.bookings) {
        await _loadBookings();
      } else {
        await _loadVenue();
      }
      if (mounted) _showMessage('登录已恢复，请重新确认操作');
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  List<String> _bookingDays(Map<String, dynamic> overview) {
    final raw = overview['bookingDays'];
    if (raw is! List) return [];
    final days = <String>{};
    for (final item in raw) {
      final value = item is Map ? item['day'] : item;
      final day = ThereBookingClient.string(value);
      if (day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
        days.add(day);
      }
    }
    final today = ThereBookingClient.schoolDay();
    final date = DateTime.parse(today);
    final next = DateTime.utc(date.year, date.month, date.day + 1);
    final tomorrow = '${next.year.toString().padLeft(4, '0')}-'
        '${next.month.toString().padLeft(2, '0')}-'
        '${next.day.toString().padLeft(2, '0')}';
    return [
      if (days.contains(today)) today,
      if (days.contains(tomorrow)) tomorrow
    ];
  }

  bool _isBookable(Map<String, dynamic> room) =>
      room['disabled'] != true &&
      room['isBusy'] != true &&
      room['isBooked'] != true &&
      ThereBookingClient.strings(room['abilities']).contains('booking');

  String _bookingTime(Object? value) {
    final text = ThereBookingClient.string(value);
    if (text == null || text.length < 16) return text ?? '待确认';
    final year = int.tryParse(text.substring(0, 4));
    final currentYear =
        DateTime.now().toUtc().add(const Duration(hours: 8)).year;
    return year == currentYear ? text.substring(5, 16) : text.substring(0, 16);
  }

  String _friendlyError(Object error) {
    if (error is ThereBookingException) return error.message;
    return '图书馆预约暂时无法使用，请稍后重试';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
