import 'package:hive/hive.dart';
import 'payment_record.dart';

part 'student.g.dart';

@HiveType(typeId: 1)
class Student {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String batchName;

  @HiveField(3)
  String studentClass;

  @HiveField(4)
  String? phoneNumber;

  @HiveField(5)
  String? notes;

  @HiveField(6)
  bool feesPaid;

  @HiveField(7)
  DateTime entryDate;

  @HiveField(8)
  List<PaymentRecord> paymentHistory;

  @HiveField(9)
  double monthlyFees;

  @HiveField(10)
  double admissionFees;

  @HiveField(11)
  bool isAdmissionPaid;

  @HiveField(12)
  String? siblingId;

  Student({
    required this.id,
    required this.name,
    required this.batchName,
    required this.studentClass,
    this.phoneNumber,
    this.notes,
    this.feesPaid = false,
    required this.entryDate,
    List<PaymentRecord>? paymentHistory,
    this.monthlyFees = 0.0,
    this.admissionFees = 0.0,
    this.isAdmissionPaid = false,
    this.siblingId,
  }) : paymentHistory = paymentHistory ?? [];

  Student copyWith({
    String? id,
    String? name,
    String? batchName,
    String? studentClass,
    String? phoneNumber,
    String? notes,
    bool? feesPaid,
    DateTime? entryDate,
    List<PaymentRecord>? paymentHistory,
    double? monthlyFees,
    double? admissionFees,
    bool? isAdmissionPaid,
    String? siblingId,
  }) {
    return Student(
      id: id ?? this.id,
      name: name ?? this.name,
      batchName: batchName ?? this.batchName,
      studentClass: studentClass ?? this.studentClass,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      notes: notes ?? this.notes,
      feesPaid: feesPaid ?? this.feesPaid,
      entryDate: entryDate ?? this.entryDate,
      paymentHistory:
          paymentHistory ?? List<PaymentRecord>.from(this.paymentHistory),
      monthlyFees: monthlyFees ?? this.monthlyFees,
      admissionFees: admissionFees ?? this.admissionFees,
      isAdmissionPaid: isAdmissionPaid ?? this.isAdmissionPaid,
      siblingId: siblingId ?? this.siblingId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'batchName': batchName,
      'studentClass': studentClass,
      'phoneNumber': phoneNumber,
      'notes': notes,
      'feesPaid': feesPaid,
      'entryDate': entryDate.millisecondsSinceEpoch,
      'paymentHistory': paymentHistory.map((p) => p.toMap()).toList(),
      'monthlyFees': monthlyFees,
      'admissionFees': admissionFees,
      'isAdmissionPaid': isAdmissionPaid,
      'siblingId': siblingId,
    };
  }

  factory Student.fromMap(Map<String, dynamic> m) {
    final int entryMs = (m['entryDate'] is int)
        ? (m['entryDate'] as int)
        : (int.tryParse((m['entryDate'] ?? '').toString()) ??
            DateTime.now().millisecondsSinceEpoch);

    final List<PaymentRecord> payments = [];
    final dynamic rawPayments = m['paymentHistory'];
    if (rawPayments is List) {
      for (final item in rawPayments) {
        try {
          if (item is Map<String, dynamic>) {
            payments.add(PaymentRecord.fromMap(item));
          } else if (item is Map) {
            payments
                .add(PaymentRecord.fromMap(Map<String, dynamic>.from(item)));
          }
        } catch (_) {
          // ignore malformed payment entries
        }
      }
    }

    return Student(
      id: (m['id'] as String?) ?? '',
      name: (m['name'] as String?) ?? '',
      batchName: (m['batchName'] as String?) ?? '',
      studentClass: (m['studentClass'] as String?) ?? '',
      phoneNumber: m['phoneNumber'] as String?,
      notes: m['notes'] as String?,
      feesPaid: (m['feesPaid'] as bool?) ?? false,
      entryDate: DateTime.fromMillisecondsSinceEpoch(entryMs),
      paymentHistory: payments,
      monthlyFees: (m['monthlyFees'] as num?)?.toDouble() ?? 0.0,
      admissionFees: (m['admissionFees'] as num?)?.toDouble() ?? 0.0,
      isAdmissionPaid: (m['isAdmissionPaid'] as bool?) ?? false,
      siblingId: m['siblingId'] as String?,
    );
  }
}
