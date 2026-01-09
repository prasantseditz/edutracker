// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'student.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StudentAdapter extends TypeAdapter<Student> {
  @override
  final int typeId = 1;

  @override
  Student read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Student(
      id: fields[0] as String,
      name: fields[1] as String,
      batchName: fields[2] as String,
      studentClass: fields[3] as String,
      phoneNumber: fields[4] as String?,
      notes: fields[5] as String?,
      feesPaid: fields[6] as bool,
      entryDate: fields[7] as DateTime,
      paymentHistory: (fields[8] as List?)?.cast<PaymentRecord>(),
      monthlyFees: fields[9] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Student obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.batchName)
      ..writeByte(3)
      ..write(obj.studentClass)
      ..writeByte(4)
      ..write(obj.phoneNumber)
      ..writeByte(5)
      ..write(obj.notes)
      ..writeByte(6)
      ..write(obj.feesPaid)
      ..writeByte(7)
      ..write(obj.entryDate)
      ..writeByte(8)
      ..write(obj.paymentHistory)
      ..writeByte(9)
      ..write(obj.monthlyFees);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
