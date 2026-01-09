// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PaymentRecordAdapter extends TypeAdapter<PaymentRecord> {
  @override
  final int typeId = 3;

  @override
  PaymentRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PaymentRecord(
      id: fields[0] as String,
      studentId: fields[1] as String,
      month: fields[2] as DateTime,
      isPaid: fields[3] as bool,
      paymentDate: fields[4] as DateTime?,
      amount: fields[5] as double,
      createdAt: fields[6] as DateTime?,
      updatedAt: fields[7] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, PaymentRecord obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.studentId)
      ..writeByte(2)
      ..write(obj.month)
      ..writeByte(3)
      ..write(obj.isPaid)
      ..writeByte(4)
      ..write(obj.paymentDate)
      ..writeByte(5)
      ..write(obj.amount)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
