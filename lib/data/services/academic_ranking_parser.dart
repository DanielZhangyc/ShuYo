import 'dart:convert';

import '../models/academic_ranking.dart';
import '../models/common.dart';

class AcademicRankingParser {
  const AcademicRankingParser._();

  static AcademicRanking parse(
    String body, {
    String expectedStudentId = '',
    DateTime? fetchedAt,
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! JsonMap || decoded['items'] is! List) {
      throw const FormatException('教务系统返回了无法识别的排名数据');
    }
    final items = (decoded['items'] as List).whereType<JsonMap>().toList();
    final matches = expectedStudentId.isEmpty
        ? items
        : items.where((item) {
            return _studentId(item) == expectedStudentId;
          }).toList();
    if (items.isNotEmpty && matches.isEmpty) {
      throw const FormatException('教务系统返回的排名与当前学号不一致');
    }
    matches.sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));
    final item = matches.isEmpty ? const <String, dynamic>{} : matches.first;
    return AcademicRanking(
      studentId: item.isEmpty ? expectedStudentId : _studentId(item),
      academicYear: stringValue(item['xnmc']),
      term: stringValue(item['xqmc']),
      collegeName: stringValue(item['jgmc'], stringValue(item['zsxymc'])),
      majorName: stringValue(item['xxzymc'], stringValue(item['zymc'])),
      collegeRank: _positiveInt(item['njjgpjjdpm']),
      collegeCount: _positiveInt(item['njjgrs']),
      majorRank: _positiveInt(item['njxxzypjjdpm']),
      majorCount: _positiveInt(item['njxxzyrs']),
      fetchedAt: fetchedAt ?? DateTime.now(),
    );
  }

  static String _sortKey(JsonMap item) {
    final year = int.tryParse(stringValue(item['xnm'])) ?? 0;
    final term = int.tryParse(stringValue(item['xqm'])) ?? 0;
    return '${year.toString().padLeft(4, '0')}-'
        '${term.toString().padLeft(3, '0')}-'
        '${stringValue(item['czsj'])}';
  }

  static int? _positiveInt(Object? value) {
    final parsed = int.tryParse(stringValue(value));
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static String _studentId(JsonMap item) {
    final internalId = stringValue(item['xh_id']).trim();
    return internalId.isNotEmpty ? internalId : stringValue(item['xh']).trim();
  }
}
