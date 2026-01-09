import 'package:hive/hive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

part 'payment_record.g.dart';

@HiveType(typeId: 3)
class PaymentRecord {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String studentId;

  @HiveField(2)
  final DateTime month;

  @HiveField(3)
  bool isPaid;

  @HiveField(4)
  DateTime? paymentDate;

  @HiveField(5)
  final double amount;

  @HiveField(6)
  final DateTime createdAt;

  @HiveField(7)
  final DateTime updatedAt;

  PaymentRecord({
    required this.id,
    required this.studentId,
    required this.month,
    required this.isPaid,
    this.paymentDate,
    this.amount = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  PaymentRecord copyWith({
    String? id,
    String? studentId,
    DateTime? month,
    bool? isPaid,
    DateTime? paymentDate,
    double? amount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentRecord(
      id: id ?? this.id,
      studentId: studentId ?? this.studentId,
      month: month ?? this.month,
      isPaid: isPaid ?? this.isPaid,
      paymentDate: paymentDate ?? this.paymentDate,
      amount: amount ?? this.amount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'studentId': studentId,
      'month': month.millisecondsSinceEpoch,
      'isPaid': isPaid,
      'paymentDate': paymentDate?.millisecondsSinceEpoch,
      'amount': amount,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> m) {
    // -------- month parse --------
    dynamic monthRaw = m['month'];
    int monthEpoch;
    try {
      if (monthRaw is int) {
        monthEpoch = monthRaw;
      } else if (monthRaw is String) {
        monthEpoch =
            int.tryParse(monthRaw) ?? DateTime.now().millisecondsSinceEpoch;
      } else if (monthRaw is Timestamp) {
        monthEpoch = monthRaw.millisecondsSinceEpoch;
      } else {
        monthEpoch = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (_) {
      monthEpoch = DateTime.now().millisecondsSinceEpoch;
    }

    // -------- paymentDate parse (FIXED) --------
    dynamic paymentDateRaw = m['paymentDate'];
    DateTime? paymentDateParsed;

    try {
      if (paymentDateRaw == null) {
        paymentDateParsed = null;
      } else if (paymentDateRaw is int) {
        paymentDateParsed = DateTime.fromMillisecondsSinceEpoch(paymentDateRaw);
      } else if (paymentDateRaw is String) {
        final v = int.tryParse(paymentDateRaw);
        paymentDateParsed =
            v != null ? DateTime.fromMillisecondsSinceEpoch(v) : null;
      } else if (paymentDateRaw is Timestamp) {
        paymentDateParsed = paymentDateRaw.toDate();
      } else {
        paymentDateParsed = null;
      }
    } catch (_) {
      paymentDateParsed = null;
    }

    // -------- amount --------
    final double amount = (m['amount'] as num?)?.toDouble() ?? 0.0;

    // -------- createdAt --------
    DateTime createdAtParsed;
    try {
      final raw = m['createdAt'];
      if (raw is int) {
        createdAtParsed = DateTime.fromMillisecondsSinceEpoch(raw);
      } else if (raw is String) {
        final v = int.tryParse(raw);
        createdAtParsed =
            v != null ? DateTime.fromMillisecondsSinceEpoch(v) : DateTime.now();
      } else if (raw is Timestamp) {
        createdAtParsed = raw.toDate();
      } else {
        createdAtParsed = DateTime.now();
      }
    } catch (_) {
      createdAtParsed = DateTime.now();
    }

    // -------- updatedAt --------
    DateTime updatedAtParsed;
    try {
      final raw = m['updatedAt'];
      if (raw is int) {
        updatedAtParsed = DateTime.fromMillisecondsSinceEpoch(raw);
      } else if (raw is String) {
        final v = int.tryParse(raw);
        updatedAtParsed =
            v != null ? DateTime.fromMillisecondsSinceEpoch(v) : DateTime.now();
      } else if (raw is Timestamp) {
        updatedAtParsed = raw.toDate();
      } else {
        updatedAtParsed = DateTime.now();
      }
    } catch (_) {
      updatedAtParsed = DateTime.now();
    }

    return PaymentRecord(
      id: (m['id'] as String?) ?? '',
      studentId: (m['studentId'] as String?) ?? '',
      month: DateTime.fromMillisecondsSinceEpoch(monthEpoch),
      isPaid: (m['isPaid'] as bool?) ?? false,
      paymentDate: paymentDateParsed,
      amount: amount,
      createdAt: createdAtParsed,
      updatedAt: updatedAtParsed,
    );
  }
}
