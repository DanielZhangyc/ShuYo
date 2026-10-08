import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/academic_schedule.dart';
import '../../data/repositories/academic_schedule_repository.dart';
import '../../data/services/schedule_share_service.dart';
import '../../data/services/student_identity_service.dart';
import '../../shared/navigation/shuyo_route.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../settings/student_identity_page.dart';
import 'academic_schedule_page.dart';

class ScheduleSharePage extends StatefulWidget {
  const ScheduleSharePage({
    super.key,
    required this.ownSchedule,
    required this.ownWeekState,
    required this.scheduleRepository,
    required this.identityService,
    this.shareApi,
    this.importStore,
    this.calendarStore,
  });

  final AcademicSchedule? ownSchedule;
  final ScheduleWeekState? ownWeekState;
  final AcademicScheduleRepository scheduleRepository;
  final StudentIdentityService? identityService;
  final ScheduleShareApi? shareApi;
  final ImportedScheduleStore? importStore;
  final TermCalendarStore? calendarStore;

  @override
  State<ScheduleSharePage> createState() => _ScheduleSharePageState();
}

class _ScheduleSharePageState extends State<ScheduleSharePage> {
  late final _api = widget.shareApi ?? ScheduleShareApi();
  late final _store = widget.importStore ?? ImportedScheduleStore();
  late final _calendars = widget.calendarStore ?? TermCalendarStore();
  final _importController = TextEditingController();
  ShareCodeInfo? _code;
  List<ImportedSchedule> _imports = const [];
  bool _generatingMode = true;
  bool _busy = false;
  bool _loading = true;
  bool _includeNote = false;
  String? _pendingRequestId;

  @override
  void initState() {
    super.initState();
    widget.identityService?.addListener(_identityChanged);
    _load();
  }

  void _identityChanged() {
    if (!mounted || widget.identityService?.isVerified != false) return;
    setState(() { _code = null; _pendingRequestId = null; });
  }

  @override
  void dispose() {
    widget.identityService?.removeListener(_identityChanged);
    _importController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final imports = await _store.list();
      if (mounted) {
        setState(() {
          _imports = imports;
          _loading = false;
        });
      }
      final own = widget.ownSchedule;
      final weekState = widget.ownWeekState;
      if (own != null && weekState != null) {
        await _calendars.save('${own.term.yearCode}:${own.term.termCode}',
            weekState.firstWeekStart);
      }
      ShareCodeInfo? code;
      try {
        final session = await widget.identityService?.checkCurrentSession();
        if (session != null) {
          code = await _api.current(session.token);
          final latest = await widget.identityService?.loadLocalSession();
          if (latest?.token != session.token) code = null;
        }
      } on Object {
        // Local imported schedules stay available without the server.
      }
      if (mounted) {
        setState(() {
          _code = code;
          if (code != null) _includeNote = code.includeNote;
        });
      }
    } on Object {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  String _newRequestId() {
    final random = Random.secure();
    return base64Url
        .encode(List<int>.generate(18, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<void> _openIdentity() async {
    final service = widget.identityService;
    if (service == null) return;
    await Navigator.of(context).push<void>(
      shuyoRoute(builder: (_) => StudentIdentityPage(service: service)),
    );
    if (mounted) await _load();
  }

  Future<void> _generate() async {
    final own = widget.ownSchedule;
    if (own == null) {
      _snack('请先同步课表');
      return;
    }
    if (_busy) return;
    final service = widget.identityService;
    if (service == null || !await service.ensureForProtectedAction()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('请先完成身份验证'),
        action: SnackBarAction(label: '去验证', onPressed: _openIdentity),
      ));
      return;
    }
    if (!mounted) return;
    if (_code != null && _pendingRequestId == null) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重新生成分享码'),
          content: const Text('旧分享码将立即失效。'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('生成')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }
    final session = await service.loadLocalSession();
    if (session == null) {
      _snack('请先完成身份验证');
      return;
    }
    if (own.term.studentId.isEmpty || own.term.studentId != session.studentId) {
      _snack('校园账户已切换，请重新打开课表');
      return;
    }
    setState(() => _busy = true);
    _pendingRequestId ??= _newRequestId();
    try {
      final code = await _api.generate(session.token, own,
          includeNote: _includeNote, requestId: _pendingRequestId!);
      if (!mounted) return;
      setState(() {
        _code = code;
        _pendingRequestId = null;
      });
      _snack('分享码已生成');
    } on Object catch (error) {
      _snack('生成失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _destroy() async {
    if (_code == null || _busy) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('销毁分享码'),
        content: const Text('销毁后，旧码无法再导入课表。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('销毁')),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    StudentIdentitySession? session;
    try {
      session = await widget.identityService?.checkCurrentSession();
    } on Object catch (error) {
      _snack('销毁失败：$error');
      return;
    }
    if (session == null) {
      _snack('请先完成身份验证');
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.destroy(session.token);
      if (!mounted) return;
      setState(() {
        _code = null;
        _pendingRequestId = null;
      });
      _snack('已销毁');
    } on Object catch (error) {
      _snack('销毁失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final code = _importController.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(code)) {
      _snack('请输入 6 位分享码');
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _api.resolve(code);
      final item = await _store.save(result);
      if (!mounted) return;
      _importController.clear();
      setState(() =>
          _imports = [item, ..._imports.where((value) => value.id != item.id)]);
      _snack('已导入');
    } on Object catch (error) {
      _snack('导入失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<ScheduleWeekState?> _weekStateFor(ImportedSchedule item) async {
    final own = widget.ownSchedule;
    if (own != null &&
        '${own.term.yearCode}:${own.term.termCode}' == item.termKey &&
        widget.ownWeekState != null) {
      return widget.ownWeekState;
    }
    var monday = await _calendars.load(item.termKey);
    if (monday == null && mounted) {
      final picked = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
        helpText: '设置该学期开学日期',
      );
      if (picked == null) return null;
      await _calendars.save(item.termKey, picked);
      monday = AcademicScheduleRepository.startOfWeek(picked);
    }
    return monday == null
        ? null
        : ScheduleWeekState(currentWeek: 1, anchorMonday: monday);
  }

  Future<void> _openImported(ImportedSchedule item) async {
    final weekState = await _weekStateFor(item);
    if (!mounted || weekState == null) return;
    final own = widget.ownSchedule;
    final sameTerm = own != null &&
        '${own.term.yearCode}:${own.term.termCode}' == item.termKey;
    await Navigator.of(context).push<void>(shuyoRoute(
      builder: (_) => ImportedSchedulePage(
        schedule:
            item.toSchedule(localWeekCount: sameTerm ? own.maxWeek : null),
        weekState: weekState,
        title: item.name,
        importId: item.id,
        onCompare: () => _openCompare(item, weekState),
      ),
    ));
  }

  Future<void> _openCompare(
      ImportedSchedule item, ScheduleWeekState weekState) async {
    await Navigator.of(context).push<void>(shuyoRoute(
      builder: (_) => ScheduleComparePickerPage(
        subject: item,
        imports: _imports,
        ownSchedule: widget.ownSchedule,
        weekState: weekState,
      ),
    ));
  }

  Future<void> _itemAction(ImportedSchedule item, String action) async {
    if (action == 'rename') {
      final controller = TextEditingController(text: item.name);
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('重命名'),
          content:
              TextField(controller: controller, maxLength: 40, autofocus: true),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, controller.text.trim()),
                child: const Text('保存')),
          ],
        ),
      );
      controller.dispose();
      if (name == null || name.isEmpty) return;
      try {
        await _store.rename(item, name);
        if (mounted) {
          setState(() => _imports = [
                for (final value in _imports)
                  value.id == item.id ? value.copyWith(name: name) : value,
              ]);
        }
      } on Object catch (error) {
        _snack('重命名失败：$error');
      }
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除导入课表'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (approved != true) return;
    await _store.delete(item.id);
    if (mounted) {
      setState(() =>
          _imports = _imports.where((value) => value.id != item.id).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.shuyoColors;
    return Scaffold(
      appBar: AppBar(title: const Text('分享与导入')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                            child: SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: true, label: Text('生成分享码')),
                            ButtonSegment(value: false, label: Text('导入')),
                          ],
                          selected: {_generatingMode},
                          onSelectionChanged: (value) =>
                              setState(() => _generatingMode = value.first),
                        )),
                        if (_generatingMode && _code != null)
                          PopupMenuButton<String>(
                            tooltip: '更多',
                            onSelected: (_) => _destroy(),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'destroy', child: Text('销毁'))
                            ],
                          ),
                      ]),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _generatingMode
                            ? Container(
                                key: const ValueKey('generate'),
                                decoration: BoxDecoration(
                                    color: colors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(999)),
                                padding: const EdgeInsets.only(left: 16),
                                child: Row(children: [
                                  Expanded(
                                      child: SelectableText(
                                          _code?.code ?? '暂无分享码',
                                          style: const TextStyle(
                                              fontSize: 17, letterSpacing: 2))),
                                  TextButton(
                                      onPressed: _busy ? null : _generate,
                                      child: Text(_pendingRequestId == null
                                          ? '生成'
                                          : '重试')),
                                  IconButton(
                                      tooltip: '复制',
                                      onPressed: _code == null || _busy
                                          ? null
                                          : () async {
                                              await Clipboard.setData(
                                                  ClipboardData(
                                                      text: _code!.code));
                                              _snack('已复制');
                                            },
                                      icon: const Icon(Icons.copy_outlined)),
                                ]),
                              )
                            : Container(
                                key: const ValueKey('import'),
                                decoration: BoxDecoration(
                                    color: colors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(999)),
                                padding: const EdgeInsets.only(left: 16),
                                child: Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: _importController,
                                          maxLength: 6,
                                          decoration: const InputDecoration(
                                              hintText: '输入分享码',
                                              counterText: '',
                                              border: InputBorder.none))),
                                  TextButton(
                                      onPressed: _busy ? null : _import,
                                      child: const Text('导入')),
                                ]),
                              ),
                      ),
                      if (_generatingMode) ...[
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                              title: const Text('新码包含备注'),
                          value: _includeNote,
                          onChanged: _busy
                              ? null
                              : (value) => setState(() {
                                    _includeNote = value ?? false;
                                    _pendingRequestId = null;
                                  }),
                        ),
                        if (_code != null)
                          Text(
                              '有效至 ${_code!.expiresAt.toLocal().year}-'
                              '${_code!.expiresAt.toLocal().month.toString().padLeft(2, '0')}-'
                              '${_code!.expiresAt.toLocal().day.toString().padLeft(2, '0')}',
                              style: TextStyle(
                                  color: colors.textMuted, fontSize: 12)),
                      ],
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                for (final item in _imports)
                  Card(
                      child: ListTile(
                    title: Text(item.name),
                    onTap: () => _openImported(item),
                    trailing: PopupMenuButton<String>(
                      tooltip: '更多',
                      onSelected: (action) => _itemAction(item, action),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('重命名')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  )),
              ],
            ),
    );
  }
}

class ScheduleComparePickerPage extends StatefulWidget {
  const ScheduleComparePickerPage({
    super.key,
    required this.subject,
    required this.imports,
    required this.ownSchedule,
    required this.weekState,
  });

  final ImportedSchedule subject;
  final List<ImportedSchedule> imports;
  final AcademicSchedule? ownSchedule;
  final ScheduleWeekState weekState;

  @override
  State<ScheduleComparePickerPage> createState() =>
      _ScheduleComparePickerPageState();
}

class _ScheduleComparePickerPageState extends State<ScheduleComparePickerPage> {
  final Set<String> _selected = {};
  bool get _ownMatches =>
      widget.ownSchedule != null &&
      '${widget.ownSchedule!.term.yearCode}:${widget.ownSchedule!.term.termCode}' ==
          widget.subject.termKey;

  void _compare() {
    if (_selected.isEmpty) return;
    final selected = <AcademicSchedule>[
      widget.subject.toSchedule(
          localWeekCount: _ownMatches ? widget.ownSchedule!.maxWeek : null),
      if (_selected.contains('own') && _ownMatches)
        widget.ownSchedule!.copyWith(
            teachingWeekCount: max(widget.ownSchedule!.maxWeek,
                widget.ownSchedule!.term.termName == '夏' ? 4 : 16)),
      for (final item in widget.imports)
        if (_selected.contains(item.id))
          item.toSchedule(
              localWeekCount: _ownMatches ? widget.ownSchedule!.maxWeek : null),
    ];
    Navigator.of(context).push<void>(shuyoRoute(
      builder: (_) =>
          SharedFreeTimePage(schedules: selected, weekState: widget.weekState),
    ));
  }

  Widget _option(String id, String name,
      {required bool enabled, bool locked = false}) {
    return CheckboxListTile(
      title: Text(name),
      value: locked || _selected.contains(id),
      onChanged: !enabled || locked
          ? null
          : (value) => setState(() {
                if (value == true) {
                  _selected.add(id);
                } else {
                  _selected.remove(id);
                }
              }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('选择课表')),
        body: ListView(children: [
          _option(widget.subject.id, widget.subject.name,
              enabled: true, locked: true),
          if (widget.ownSchedule != null)
            _option('own', '我的课表', enabled: _ownMatches),
          for (final item in widget.imports)
            if (item.id != widget.subject.id)
              _option(item.id, item.name,
                  enabled: item.termKey == widget.subject.termKey),
        ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
              onPressed: _selected.isEmpty ? null : _compare,
              child: const Text('比较')),
        )),
      );
}
