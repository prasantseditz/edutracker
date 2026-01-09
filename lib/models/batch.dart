import 'package:hive/hive.dart';
import 'student.dart';

part 'batch.g.dart';

@HiveType(typeId: 2)
class Batch {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String studentClass;

  @HiveField(3)
  final List<Student> students;

  @HiveField(4)
  double defaultFees;

  @HiveField(5)
  String feesCycle; // 'monthly', 'bi_monthly', 'quarterly'

  @HiveField(6)
  bool postponed;

  DateTime? lastUpdated; // not a Hive field, optional

  Batch({
    required this.id,
    required this.name,
    required this.studentClass,
    List<Student>? students,
    this.lastUpdated,
    this.defaultFees = 0.0,
    this.feesCycle = 'monthly',
    this.postponed = false,
  }) : students = students ?? <Student>[];

  Batch copyWith({
    String? id,
    String? name,
    String? studentClass,
    List<Student>? students,
    DateTime? lastUpdated,
    double? defaultFees,
    String? feesCycle,
    bool? postponed,
  }) {
    return Batch(
      id: id ?? this.id,
      name: name ?? this.name,
      studentClass: studentClass ?? this.studentClass,
      students: students ?? List<Student>.from(this.students),
      lastUpdated: lastUpdated ?? this.lastUpdated,
      defaultFees: defaultFees ?? this.defaultFees,
      feesCycle: feesCycle ?? this.feesCycle,
      postponed: postponed ?? this.postponed,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'studentClass': studentClass,
      'students': students.map((s) => s.toMap()).toList(),
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'defaultFees': defaultFees,
      'feesCycle': feesCycle,
      'postponed': postponed,
    };
  }

  factory Batch.fromMap(Map<String, dynamic> m) {
    final rawStudents = m['students'];
    List<Student> parsedStudents = <Student>[];
    if (rawStudents is List) {
      for (final item in rawStudents) {
        try {
          if (item is Student) {
            parsedStudents.add(item);
          } else if (item is Map<String, dynamic>) {
            parsedStudents.add(Student.fromMap(item));
          } else if (item is Map) {
            parsedStudents
                .add(Student.fromMap(Map<String, dynamic>.from(item)));
          }
        } catch (_) {
          // ignore malformed student entries
        }
      }
    }

    DateTime? lastUpdatedParsed;
    try {
      final dyn = m['lastUpdated'];
      if (dyn is int) {
        lastUpdatedParsed = DateTime.fromMillisecondsSinceEpoch(dyn);
      } else if (dyn is String) {
        final v = int.tryParse(dyn);
        if (v != null) {
          lastUpdatedParsed = DateTime.fromMillisecondsSinceEpoch(v);
        }
      }
    } catch (_) {
      lastUpdatedParsed = null;
    }

    return Batch(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      studentClass: (m['studentClass'] as String?) ?? '',
      students: parsedStudents.isNotEmpty ? parsedStudents : null,
      lastUpdated: lastUpdatedParsed,
      defaultFees: (m['defaultFees'] as num?)?.toDouble() ?? 0.0,
      feesCycle: (m['feesCycle'] as String?) ?? 'monthly',
      postponed: (m['postponed'] as bool?) ?? false,
    );
  }
}
