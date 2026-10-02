import 'common.dart';

class AcademicRanking {
  const AcademicRanking({
    required this.studentId,
    required this.academicYear,
    required this.term,
    required this.collegeName,
    required this.majorName,
    required this.collegeRank,
    required this.collegeCount,
    required this.majorRank,
    required this.majorCount,
    required this.fetchedAt,
  });

  final String studentId;
  final String academicYear;
  final String term;
  final String collegeName;
  final String majorName;
  final int? collegeRank;
  final int? collegeCount;
  final int? majorRank;
  final int? majorCount;
  final DateTime fetchedAt;

  bool get hasRank => collegeRank != null || majorRank != null;

  JsonMap toJson() => {
        'studentId': studentId,
        'academicYear': academicYear,
        'term': term,
        'collegeName': collegeName,
        'majorName': majorName,
        'collegeRank': collegeRank,
        'collegeCount': collegeCount,
        'majorRank': majorRank,
        'majorCount': majorCount,
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory AcademicRanking.fromJson(JsonMap json) => AcademicRanking(
        studentId: stringValue(json['studentId']),
        academicYear: stringValue(json['academicYear']),
        term: stringValue(json['term']),
        collegeName: stringValue(json['collegeName']),
        majorName: stringValue(json['majorName']),
        collegeRank: _positiveInt(json['collegeRank']),
        collegeCount: _positiveInt(json['collegeCount']),
        majorRank: _positiveInt(json['majorRank']),
        majorCount: _positiveInt(json['majorCount']),
        fetchedAt: DateTime.tryParse(stringValue(json['fetchedAt'])) ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  static int? _positiveInt(Object? value) {
    final parsed = int.tryParse(stringValue(value));
    return parsed != null && parsed > 0 ? parsed : null;
  }
}
