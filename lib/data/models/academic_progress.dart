import 'common.dart';

class AcademicCertificate {
  const AcademicCertificate(
      {required this.name, required this.acquisitionStatus});

  final String name;
  final String acquisitionStatus;

  JsonMap toJson() => {
        'name': name,
        'acquisitionStatus': acquisitionStatus,
      };

  factory AcademicCertificate.fromJson(JsonMap json) => AcademicCertificate(
        name: stringValue(json['name']),
        acquisitionStatus: stringValue(json['acquisitionStatus']),
      );
}

class AcademicProgressCourse {
  const AcademicProgressCourse({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.credits,
    required this.grade,
    required this.gradePoint,
    required this.academicYear,
    required this.term,
    required this.suggestedYear,
    required this.suggestedTerm,
    required this.nature,
    required this.category,
    required this.hours,
  });

  final String id;
  final String code;
  final String name;
  final String status;
  final String credits;
  final String grade;
  final String gradePoint;
  final String academicYear;
  final String term;
  final String suggestedYear;
  final String suggestedTerm;
  final String nature;
  final String category;
  final String hours;

  String get statusLabel => switch (status) {
        '1' => '在修',
        '2' => '未过',
        '3' => '待修',
        '4' || '21' => '已修',
        '5' || '6' || '7' || '8' || '9' => '替代或认定',
        _ => '状态未知',
      };

  JsonMap toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'status': status,
        'credits': credits,
        'grade': grade,
        'gradePoint': gradePoint,
        'academicYear': academicYear,
        'term': term,
        'suggestedYear': suggestedYear,
        'suggestedTerm': suggestedTerm,
        'nature': nature,
        'category': category,
        'hours': hours,
      };

  factory AcademicProgressCourse.fromJson(JsonMap json) =>
      AcademicProgressCourse(
        id: stringValue(json['id']),
        code: stringValue(json['code']),
        name: stringValue(json['name']),
        status: stringValue(json['status']),
        credits: stringValue(json['credits']),
        grade: stringValue(json['grade']),
        gradePoint: stringValue(json['gradePoint']),
        academicYear: stringValue(json['academicYear']),
        term: stringValue(json['term']),
        suggestedYear: stringValue(json['suggestedYear']),
        suggestedTerm: stringValue(json['suggestedTerm']),
        nature: stringValue(json['nature']),
        category: stringValue(json['category']),
        hours: stringValue(json['hours']),
      );
}

class AcademicProgressNode {
  const AcademicProgressNode({
    required this.id,
    required this.parentId,
    required this.name,
    required this.requiredCredits,
    required this.earnedCredits,
    required this.passed,
    required this.courseKind,
    required this.isLeaf,
    this.courses = const [],
  });

  final String id;
  final String parentId;
  final String name;
  final double? requiredCredits;
  final double? earnedCredits;
  final bool? passed;
  final String courseKind;
  final bool isLeaf;
  final List<AcademicProgressCourse> courses;

  AcademicProgressNode withCourses(List<AcademicProgressCourse> value) =>
      AcademicProgressNode(
        id: id,
        parentId: parentId,
        name: name,
        requiredCredits: requiredCredits,
        earnedCredits: earnedCredits,
        passed: passed,
        courseKind: courseKind,
        isLeaf: isLeaf,
        courses: value,
      );

  JsonMap toJson() => {
        'id': id,
        'parentId': parentId,
        'name': name,
        'requiredCredits': requiredCredits,
        'earnedCredits': earnedCredits,
        'passed': passed,
        'courseKind': courseKind,
        'isLeaf': isLeaf,
        'courses': courses.map((course) => course.toJson()).toList(),
      };

  factory AcademicProgressNode.fromJson(JsonMap json) => AcademicProgressNode(
        id: stringValue(json['id']),
        parentId: stringValue(json['parentId']),
        name: stringValue(json['name']),
        requiredCredits: (json['requiredCredits'] as num?)?.toDouble(),
        earnedCredits: (json['earnedCredits'] as num?)?.toDouble(),
        passed: json['passed'] as bool?,
        courseKind: stringValue(json['courseKind']),
        isLeaf: json['isLeaf'] == true,
        courses: (json['courses'] as List? ?? const [])
            .whereType<JsonMap>()
            .map(AcademicProgressCourse.fromJson)
            .toList(),
      );
}

class AcademicProgress {
  const AcademicProgress({
    required this.studentId,
    required this.gpa,
    required this.plannedCourses,
    required this.passedCourses,
    required this.ongoingCourses,
    required this.notTakenCourses,
    required this.nodes,
    required this.fetchedAt,
    this.certificates = const [],
  });

  final String studentId;
  final String gpa;
  final int? plannedCourses;
  final int? passedCourses;
  final int? ongoingCourses;
  final int? notTakenCourses;
  final List<AcademicProgressNode> nodes;
  final DateTime fetchedAt;
  final List<AcademicCertificate> certificates;

  AcademicProgressNode? node(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  List<AcademicProgressNode> childrenOf(String parentId) =>
      nodes.where((node) => node.parentId == parentId).toList();

  AcademicProgressNode? get mainNode {
    for (final node in nodes) {
      if (node.parentId.isEmpty) return node;
    }
    return null;
  }

  JsonMap toJson() => {
        'studentId': studentId,
        'gpa': gpa,
        'plannedCourses': plannedCourses,
        'passedCourses': passedCourses,
        'ongoingCourses': ongoingCourses,
        'notTakenCourses': notTakenCourses,
        'nodes': nodes.map((node) => node.toJson()).toList(),
        'certificates':
            certificates.map((certificate) => certificate.toJson()).toList(),
        'fetchedAt': fetchedAt.toIso8601String(),
      };

  factory AcademicProgress.fromJson(JsonMap json) {
    final nodes = (json['nodes'] as List? ?? const [])
        .whereType<JsonMap>()
        .map(AcademicProgressNode.fromJson)
        .toList();
    if (!nodes.any((node) => node.id == 'zgzsxx')) {
      final otherCoursesIndex =
          nodes.indexWhere((node) => node.id == 'qtkcxfyq');
      nodes.insert(
        otherCoursesIndex < 0 ? nodes.length : otherCoursesIndex,
        const AcademicProgressNode(
          id: 'zgzsxx',
          parentId: '',
          name: '资格证书信息',
          requiredCredits: null,
          earnedCredits: null,
          passed: null,
          courseKind: 'certificate',
          isLeaf: true,
        ),
      );
    }
    return AcademicProgress(
      studentId: stringValue(json['studentId']),
      gpa: stringValue(json['gpa']),
      plannedCourses: int.tryParse(stringValue(json['plannedCourses'])),
      passedCourses: int.tryParse(stringValue(json['passedCourses'])),
      ongoingCourses: int.tryParse(stringValue(json['ongoingCourses'])),
      notTakenCourses: int.tryParse(stringValue(json['notTakenCourses'])),
      nodes: nodes,
      certificates: (json['certificates'] as List? ?? const [])
          .whereType<JsonMap>()
          .map(AcademicCertificate.fromJson)
          .toList(),
      fetchedAt: DateTime.tryParse(stringValue(json['fetchedAt'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
