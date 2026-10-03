import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/academic_account_store.dart';
import '../../data/services/there_booking_client.dart';
import '../../data/services/unified_account_service.dart';
import '../../shared/widgets/empty_state.dart';
import '../auth/native_login_page.dart';

class LibraryBookingPage extends StatefulWidget {
  const LibraryBookingPage({
    super.key,
    required this.accountService,
    this.client,
  });

  final UnifiedAccountService accountService;
  final ThereBookingClient? client;

  @override
  State<LibraryBookingPage> createState() => _LibraryBookingPageState();
}

class _LibraryBookingPageState extends State<LibraryBookingPage> {
  late final ThereBookingClient _client = widget.client ?? ThereBookingClient();
  BookingVenue _venue = BookingVenue.library;
  String _day = ThereBookingClient.schoolDay();
  List<String> _days = [];
  List<Map<String, dynamic>> _areas = [];
  Map<String, dynamic>? _selectedArea;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _areaData;
  List<Map<String, dynamic>> _rooms = [];
  List<Map<String, dynamic>> _recent = [];
  String _start = '08:30';
  String _end = '09:30';
  String _seatFilter = '';
  bool _onlyAvailable = true;
  String? _selectedRoomId;
  String? _error;
  bool _loading = true;
  bool _loadingSeats = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadVenue());
  }

  @override
  void dispose() {
    if (widget.client == null) _client.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('图书馆预约'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _busy || _loading ? null : () => _loadVenue(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? EmptyState(
                  icon: _error!.contains('校园网')
                      ? Icons.wifi_off_outlined
                      : Icons.event_busy_outlined,
                  title: _error!.contains('校园网') ? '暂时无法访问预约系统' : '加载失败',
                  message: _error!,
                  action: TextButton.icon(
                    onPressed: _loadVenue,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadVenue,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: [
                      _venueSelector(),
                      const SizedBox(height: 22),
                      _sectionTitle('我的预约'),
                      const SizedBox(height: 8),
                      _recentSection(),
                      const SizedBox(height: 24),
                      _sectionTitle('预约座位'),
                      const SizedBox(height: 12),
                      _searchControls(),
                      const SizedBox(height: 14),
                      _seatSection(),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _busy ||
                                _loadingSeats ||
                                _selectedArea == null ||
                                _selectedRoomId == null
                            ? null
                            : _createBooking,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.event_available_outlined),
                        label: const Text('确认预约'),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _venueSelector() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final venue in BookingVenue.values) ...[
              ChoiceChip(
                label: Text(venue.label),
                selected: venue == _venue,
                onSelected: _busy || _loading || _loadingSeats
                    ? null
                    : (_) {
                        if (venue == _venue) return;
                        setState(() => _venue = venue);
                        unawaited(_loadVenue());
                      },
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      );

  Widget _sectionTitle(String title) => Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _recentSection() {
    final entries =
        _recent.where((item) => item['roomType'] == _venue.roomType).toList();
    if (entries.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Text('暂无最近预约'),
        ),
      );
    }
    return Column(
      children: [
        for (final item in entries)
          Card(
            child: ListTile(
              title: Text(
                '${ThereBookingClient.string(item['roomName']) ?? '座位'} · '
                '${ThereBookingClient.string(item['officeAreaName']) ?? _venue.label}',
              ),
              subtitle: Text(
                '${_shortDateTime(item['beginTime'])} — '
                '${_shortDateTime(item['endTime'])}\n'
                '${ThereBookingClient.string(item['statusLabel']) ?? ThereBookingClient.string(item['status']) ?? '状态待确认'}',
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openDetail(item),
            ),
          ),
      ],
    );
  }

  Widget _searchControls() {
    final areaId = ThereBookingClient.string(_selectedArea?['id']);
    return Column(
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('day-${_venue.name}-$_day'),
          initialValue: _days.contains(_day) ? _day : null,
          decoration: const InputDecoration(
            labelText: '日期',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final day in _days)
              DropdownMenuItem(value: day, child: Text(day)),
          ],
          onChanged: _busy || _loadingSeats
              ? null
              : (value) {
                  if (value == null || value == _day) return;
                  setState(() => _day = value);
                  unawaited(_loadVenue());
                },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('area-${_venue.name}-$_day-$areaId'),
          initialValue:
              _areas.any((item) => item['id'] == areaId) ? areaId : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '区域',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final area in _areas)
              if (ThereBookingClient.string(area['id']) case final String id)
                DropdownMenuItem(
                  value: id,
                  child: Text(
                    ThereBookingClient.string(area['name']) ?? '未命名区域',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
          onChanged: _busy || _loadingSeats
              ? null
              : (value) {
                  if (value == null || value == areaId) return;
                  final selected = _areas.firstWhere(
                    (area) => area['id'] == value,
                  );
                  setState(() => _selectedArea = selected);
                  unawaited(_loadArea());
                },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _timeButton('开始', _start, true)),
            const SizedBox(width: 12),
            Expanded(child: _timeButton('结束', _end, false)),
          ],
        ),
        if (_areaData != null) ...[
          const SizedBox(height: 8),
          Text(
            _rulesText(_areaData!['bookingTimes']),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _timeButton(String label, String value, bool start) => OutlinedButton(
        onPressed: _busy || _loadingSeats ? null : () => _pickTime(start),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value),
            ],
          ),
        ),
      );

  Widget _seatSection() {
    if (_loadingSeats) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_selectedArea == null) return const Text('当前场馆没有可选区域');
    if (_rooms.isEmpty) return const Text('所选时段没有返回座位，请更换区域或时间');
    final available = _rooms.where(_isBookable).length;
    final visible = _rooms.where((room) {
      final name = ThereBookingClient.string(room['name']) ?? '';
      return (!_onlyAvailable || _isBookable(room)) &&
          name.toLowerCase().contains(_seatFilter.toLowerCase());
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('可选座位 $available / ${_rooms.length}'),
        const SizedBox(height: 10),
        TextField(
          decoration: const InputDecoration(
            hintText: '搜索座位号',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _seatFilter = value.trim()),
        ),
        const SizedBox(height: 8),
        FilterChip(
          label: const Text('只看可预约'),
          selected: _onlyAvailable,
          onSelected: (value) => setState(() => _onlyAvailable = value),
        ),
        const SizedBox(height: 8),
        if (visible.isEmpty) const Text('没有符合条件的座位'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final room in visible)
              if (ThereBookingClient.string(room['id']) case final String id)
                ChoiceChip(
                  label: Text(ThereBookingClient.string(room['name']) ?? id),
                  selected: _selectedRoomId == id,
                  onSelected: !_isBookable(room) || _busy
                      ? null
                      : (_) => setState(() => _selectedRoomId = id),
                ),
          ],
        ),
      ],
    );
  }

  Future<void> _loadVenue() async {
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _selectedRoomId = null;
    });
    try {
      _profile = await _read(() async {
        await _client.selectVenue(_venue);
        return _client.profile();
      });
      await _checkAccount(_profile!);
      final recent = await _read(_client.recent);
      var overview = await _read(() => _client.overview(_day));
      final dayOptions = _bookingDays(overview);
      if (dayOptions.isNotEmpty && !dayOptions.contains(_day)) {
        _day = dayOptions.first;
        overview = await _read(() => _client.overview(_day));
      }
      final areas = await _read(() => _client.areas(_day));
      if (!mounted || generation != _generation) return;
      final matching = areas
          .where((area) => ThereBookingClient.strings(area['supportRoomTypes'])
              .contains(_venue.roomType))
          .toList();
      final oldAreaId = ThereBookingClient.string(_selectedArea?['id']);
      final selected = matching
              .where((area) => area['id'] == oldAreaId)
              .firstOrNull ??
          matching
              .where(
                  (area) => ThereBookingClient.string(area['parentId']) != null)
              .firstOrNull ??
          matching.firstOrNull;
      setState(() {
        _recent = recent;
        _days = dayOptions.isEmpty ? [_day] : dayOptions;
        _areas = matching;
        _selectedArea = selected;
        _areaData = null;
        _rooms = [];
        _loading = false;
      });
      if (selected != null) await _loadArea();
      try {
        await widget.accountService.setTherePendingRecovery(false);
      } on Object {
        // Business data is available even if the local status marker fails.
      }
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      try {
        await widget.accountService.setTherePendingRecovery(true);
      } on Object {
        // Keep the concrete service error visible to the user.
      }
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
    if (!mounted) return false;
    final result = await Navigator.of(context).push<NativeLoginResult>(
      MaterialPageRoute(builder: (_) => const NativeLoginPage.there()),
    );
    if (result == NativeLoginResult.authenticated) {
      _client.resetSession();
      return true;
    }
    return false;
  }

  Future<T> _read<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on ThereBookingException catch (error) {
      if (error.kind != ThereFailureKind.loginRequired) rethrow;
    }
    final authenticated = await _authenticate();
    if (!authenticated) {
      throw const ThereBookingException(
        ThereFailureKind.loginRequired,
        '请先登录图书馆预约',
      );
    }
    await _client.selectVenue(_venue);
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

  Future<void> _loadArea() async {
    final area = _selectedArea;
    final id = ThereBookingClient.string(area?['id']);
    if (id == null || !mounted) return;
    final generation = ++_generation;
    setState(() {
      _loadingSeats = true;
      _selectedRoomId = null;
      _rooms = [];
    });
    try {
      final data = await _read(() => _client.area(id, _day, _day));
      final rules = ThereBookingClient.object(data['bookingTimes']) ?? const {};
      final start =
          ThereBookingClient.string(rules['suggestStartTime']) ?? _start;
      final end = ThereBookingClient.string(rules['suggestEndTime']) ?? _end;
      if (!mounted || generation != _generation) return;
      setState(() {
        _areaData = data;
        _start = start;
        _end = end;
      });
      await _refreshSeats();
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _loadingSeats = false);
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _refreshSeats() async {
    final id = ThereBookingClient.string(_selectedArea?['id']);
    if (id == null || !mounted) return;
    final generation = ++_generation;
    setState(() {
      _loadingSeats = true;
      _selectedRoomId = null;
    });
    try {
      if (_end.compareTo(_start) <= 0) {
        throw const ThereBookingException(
          ThereFailureKind.business,
          '结束时间需要晚于开始时间',
        );
      }
      final result = await _read(() => _client.area(
            id,
            '$_day $_start',
            '$_day $_end',
          ));
      if (!mounted || generation != _generation) return;
      setState(() {
        _areaData = result;
        _rooms = ThereBookingClient.objects(result['rooms']);
        _loadingSeats = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _rooms = [];
        _loadingSeats = false;
      });
      _showMessage(_friendlyError(error));
    }
  }

  Future<void> _pickTime(bool start) async {
    final original = start ? _start : _end;
    final parts = original.split(':');
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 8,
        minute: int.tryParse(parts.last) ?? 30,
      ),
      helpText: start ? '选择开始时间' : '选择结束时间',
    );
    if (time == null || !mounted) return;
    final value = '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (start) {
        _start = value;
      } else {
        _end = value;
      }
    });
    await _refreshSeats();
  }

  Future<void> _createBooking() async {
    final areaId = ThereBookingClient.string(_selectedArea?['id']);
    final roomId = _selectedRoomId;
    if (_busy || areaId == null || roomId == null) return;
    final room = _rooms.where((item) => item['id'] == roomId).firstOrNull;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('确认预约？'),
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
                child: const Text('提交预约'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    String? createdId;
    try {
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
          if (mounted) setState(() => _recent = recent);
        } on Object {
          // Keep the uncertain result; a new create request is not automatic.
        }
      }
      if (error.kind == ThereFailureKind.loginRequired) {
        await _recoverAfterWrite();
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
      final detail = await _read(() => _client.detail(id));
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('预约详情', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 14),
                Text(
                    '${ThereBookingClient.string(detail['allOfficeAreaName']) ?? _venue.label}\n'
                    '座位：${ThereBookingClient.string(detail['roomName']) ?? '未知'}\n'
                    '时间：${_shortDateTime(detail['beginTime'])} — '
                    '${_shortDateTime(detail['endTime'])}\n'
                    '状态：${ThereBookingClient.string(detail['statusLabel']) ?? ThereBookingClient.string(detail['status']) ?? '待确认'}'),
                const SizedBox(height: 18),
                if (ThereBookingClient.strings(detail['abilities'])
                    .contains('cancel'))
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_cancelBooking(id));
                    },
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('取消预约'),
                  ),
                if (ThereBookingClient.strings(detail['abilities'])
                    .contains('close'))
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      unawaited(_finishBooking(id));
                    },
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('提前结束'),
                  ),
              ],
            ),
          ),
        ),
      );
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  Future<void> _cancelBooking(String id) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('取消这条预约？'),
            content: const Text('取消后需要重新预约座位。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保留预约'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认取消'),
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
      if (error.kind == ThereFailureKind.loginRequired) {
        await _recoverAfterWrite();
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
    try {
      final recent = await _read(_client.recent);
      if (!mounted) return;
      setState(() => _recent = recent);
      await _refreshSeats();
    } on Object {
      if (mounted) _showMessage('已取消预约，列表暂时无法刷新');
    }
  }

  Future<void> _finishBooking(String id) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('提前结束这条预约？'),
            content: const Text('提交后请以服务端返回的最终状态和时间为准。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('返回'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('确认结束'),
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
      if (error.kind == ThereFailureKind.loginRequired) {
        await _recoverAfterWrite();
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
    try {
      final recent = await _read(_client.recent);
      if (!mounted) return;
      setState(() => _recent = recent);
      await _refreshSeats();
    } on Object {
      if (mounted) _showMessage('操作已提交，列表暂时无法刷新');
    }
  }

  Future<void> _recoverAfterWrite() async {
    try {
      if (!await _authenticate() || !mounted) return;
      await _loadVenue();
      if (mounted) _showMessage('登录已恢复，请重新确认操作');
    } on Object catch (error) {
      if (mounted) _showMessage(_friendlyError(error));
    }
  }

  List<String> _bookingDays(Map<String, dynamic> overview) {
    final raw = overview['bookingDays'];
    if (raw is! List) return [_day];
    final days = <String>{};
    for (final item in raw) {
      final value = item is Map ? item['day'] : item;
      final day = ThereBookingClient.string(value);
      if (day != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
        days.add(day);
      }
    }
    return days.isEmpty ? [_day] : (days.toList()..sort());
  }

  bool _isBookable(Map<String, dynamic> room) =>
      room['disabled'] != true &&
      room['isBusy'] != true &&
      room['isBooked'] != true &&
      ThereBookingClient.strings(room['abilities']).contains('booking');

  String _rulesText(Object? value) {
    final rules = ThereBookingClient.object(value) ?? const {};
    final min = rules['minDuration'];
    final max = rules['maxDuration'];
    final interval = rules['meetingInterval'];
    return [
      if (min is num) '最短 $min 分钟',
      if (max is num) '最长 $max 分钟',
      if (interval is num) '间隔 $interval 分钟',
    ].join(' · ');
  }

  String _shortDateTime(Object? value) {
    final text = ThereBookingClient.string(value) ?? '待确认';
    return text.length >= 16 ? text.substring(0, 16) : text;
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
