import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/academic_progress.dart';
import '../../data/repositories/academic_progress_repository.dart';
import '../../data/services/academic_schedule_api_client.dart';
import '../../shared/theme/shuyo_theme.dart';
import '../../shared/widgets/empty_state.dart';

class AcademicProgressPage extends StatefulWidget {
  const AcademicProgressPage({
    super.key,
    required this.repository,
    required this.onLoginRequired,
  });

  final AcademicProgressRepository repository;
  final Future<void> Function() onLoginRequired;

  @override
  State<AcademicProgressPage> createState() => _AcademicProgressPageState();
}

class _AcademicProgressPageState extends State<AcademicProgressPage> {
  AcademicProgress? _progress;
  final Set<String> _expandedNodes = {};
  bool _loading = true;
  bool _refreshing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCached());
  }

  Future<void> _loadCached() async {
    try {
      final progress = await widget.repository.loadCachedProgress();
      if (!mounted) return;
      setState(() {
        _progress = progress;
        if (progress != null && _expandedNodes.isEmpty) {
          final mainId = progress.mainNode?.id;
          if (mainId != null) _expandedNodes.add(mainId);
        }
        _loadError = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await _fetchAndShow();
    } on AcademicAuthException {
      if (!mounted) return;
      await widget.onLoginRequired();
      if (!mounted) return;
      try {
        await _fetchAndShow();
      } on AcademicAuthException {
        if (mounted) _showSnack('请先登录上大校园账户后再刷新');
      } on Object catch (error) {
        if (mounted) _showSnack('学业信息同步失败：$error');
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showSnack('学业信息同步失败：$error');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _fetchAndShow() async {
    final progress = await widget.repository.refreshProgress();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      final existingIds = progress.nodes.map((node) => node.id).toSet();
      _expandedNodes.removeWhere((id) => !existingIds.contains(id));
      if (_expandedNodes.isEmpty) {
        final mainId = progress.mainNode?.id;
        if (mainId != null) _expandedNodes.add(mainId);
      }
      _loadError = null;
    });
    _showSnack('学业信息已同步');
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMoreMenu() async {
    final action = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomPadding),
            decoration: BoxDecoration(
              color: context.shuyoColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: _refreshing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      )
                    : const Icon(Icons.refresh),
                title: const Text('刷新学业信息'),
                enabled: !_refreshing,
                onTap: () => Navigator.of(context).pop(true),
              ),
            ),
          ),
        );
      },
    );
    if (action == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('学业'),
        actions: [
          IconButton(
            tooltip: '更多',
            onPressed: _openMoreMenu,
            icon: const Icon(Icons.more_horiz),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }
    final progress = _progress;
    if (progress == null) {
      return EmptyState(
        icon: Icons.school_outlined,
        title: _loadError == null ? '还没有学业信息' : '读取学业信息失败',
        message: _loadError ?? '登录上大校园账户后，同步一次即可在本地查看。',
        action: FilledButton.icon(
          onPressed: _refreshing ? null : _refresh,
          icon: const Icon(Icons.refresh),
          label: Text(_refreshing ? '同步中...' : '同步学业信息'),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _overview(progress),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
          child: Text('学业结构', style: Theme.of(context).textTheme.titleMedium),
        ),
        ..._treeRows(progress, '', 0),
      ],
    );
  }

  List<Widget> _treeRows(
      AcademicProgress progress, String parentId, int depth) {
    final rows = <Widget>[];
    for (final node in progress.childrenOf(parentId)) {
      rows.add(_nodeRow(node, depth));
      if (!_expandedNodes.contains(node.id)) continue;
      if (node.id == 'zgzsxx') {
        if (progress.certificates.isEmpty) {
          rows.add(_emptyRow('暂无资格证书信息', depth + 1));
        } else {
          for (final certificate in progress.certificates) {
            rows.add(_certificateRow(certificate, depth + 1));
          }
        }
      } else if (node.isLeaf) {
        if (node.courses.isEmpty) {
          rows.add(_emptyRow('该分类暂无课程', depth + 1));
        } else {
          for (final course in node.courses) {
            rows.add(_courseRow(course, depth + 1));
          }
        }
      } else {
        rows.addAll(_treeRows(progress, node.id, depth + 1));
      }
    }
    return rows;
  }

  Widget _nodeRow(AcademicProgressNode node, int depth) {
    final colors = context.shuyoColors;
    final expanded = _expandedNodes.contains(node.id);
    final credits = _creditsText(node);
    return Padding(
      padding: EdgeInsets.only(left: _indent(depth)),
      child: Material(
        color: expanded ? colors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() {
            if (expanded) {
              _expandedNodes.remove(node.id);
            } else {
              _expandedNodes.add(node.id);
            }
          }),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                  size: 22,
                  color: expanded ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(node.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: depth == 0
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  )),
                      if (credits != null) ...[
                        const SizedBox(height: 3),
                        Text(credits,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: colors.textSecondary,
                                    )),
                      ],
                    ],
                  ),
                ),
                if (node.passed != null)
                  Icon(
                    node.passed!
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 16,
                    color: node.passed! ? colors.success : colors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _courseRow(AcademicProgressCourse course, int depth) {
    final colors = context.shuyoColors;
    final statusColor = _courseStatusColor(course, colors);
    return Padding(
      padding: EdgeInsets.only(left: _indent(depth)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showCourseDetails(course),
          child: Container(
            constraints: const BoxConstraints(minHeight: 58),
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.border, width: 2),
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: Row(
              children: [
                Column(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(course.statusLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontSize: 10,
                            )),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (course.nature.isNotEmpty) course.nature,
                          if (course.credits.isNotEmpty) '${course.credits} 学分',
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: colors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _certificateRow(AcademicCertificate certificate, int depth) {
    final colors = context.shuyoColors;
    return Padding(
      padding: EdgeInsets.only(left: _indent(depth)),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: colors.border, width: 2),
            bottom: BorderSide(color: colors.border),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_outlined,
                size: 20, color: colors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(certificate.name)),
            if (certificate.acquisitionStatus.isNotEmpty)
              Text(certificate.acquisitionStatus,
                  style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _emptyRow(String message, int depth) {
    final colors = context.shuyoColors;
    return Padding(
      padding: EdgeInsets.only(left: _indent(depth)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.border, width: 2)),
        ),
        child: Text(message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                )),
      ),
    );
  }

  double _indent(int depth) => 12.0 * depth.clamp(0, 4);

  Color _courseStatusColor(AcademicProgressCourse course, ShuYoColors colors) =>
      switch (course.status) {
        '4' || '21' => colors.success,
        '1' => colors.accent,
        '2' => colors.danger,
        '3' => colors.textMuted,
        _ => colors.warning,
      };

  Widget _overview(AcademicProgress progress) {
    final root = progress.mainNode;
    final earned = root?.earnedCredits;
    final required = root?.requiredCredits;
    final colors = context.shuyoColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学业总览', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 15),
            Row(
              children: [
                Expanded(
                  child:
                      _metric('已获学分', earned == null ? '—' : _number(earned)),
                ),
                Expanded(
                  child: _metric(
                      '要求学分', required == null ? '—' : _number(required)),
                ),
                Expanded(
                  child: _metric(
                      '平均绩点', progress.gpa.isEmpty ? '—' : progress.gpa),
                ),
              ],
            ),
            if (earned != null && required != null && required > 0) ...[
              const SizedBox(height: 15),
              LinearProgressIndicator(
                value: (earned / required).clamp(0, 1),
                minHeight: 7,
                borderRadius: BorderRadius.circular(7),
              ),
            ],
            if (progress.plannedCourses != null) ...[
              const SizedBox(height: 12),
              Text(
                '计划 ${progress.plannedCourses} 门 · 已修 ${progress.passedCourses ?? '—'} 门'
                ' · 在修 ${progress.ongoingCourses ?? '—'} 门 · 未修 ${progress.notTakenCourses ?? '—'} 门',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              '同步于 ${_dateText(progress.fetchedAt)} · 数据仅供学业修读参考',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
        ],
      );

  Future<void> _showCourseDetails(AcademicProgressCourse course) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 14),
                  _detail('课程号', course.code),
                  _detail('修读状态', course.statusLabel),
                  _detail('学分', course.credits),
                  _detail('成绩', course.grade),
                  _detail('绩点', course.gradePoint),
                  _detail(
                      '成绩学年学期', '${course.academicYear} ${course.term}'.trim()),
                  _detail('建议修读',
                      '${course.suggestedYear} ${course.suggestedTerm}'.trim()),
                  _detail('课程性质', course.nature),
                  _detail('课程类别', course.category),
                  _detail('学时', course.hours),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _detail(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$label：$value'),
    );
  }

  String? _creditsText(AcademicProgressNode node) {
    final required = node.requiredCredits;
    final earned = node.earnedCredits;
    if (required == null && earned == null) return null;
    return '已获 ${earned == null ? '—' : _number(earned)} / '
        '要求 ${required == null ? '—' : _number(required)} 学分';
  }

  String _number(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  String _dateText(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }
}
