// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'batch.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BatchAdapter extends TypeAdapter<Batch> {
  @override
  final int typeId = 2;

  @override
  Batch read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Batch(
      id: fields[0] as String,
      name: fields[1] as String,
      studentClass: fields[2] as String,
      students: (fields[3] as List?)?.cast<Student>(),
      defaultFees: fields[4] as double,
      feesCycle: fields[5] == null ? 'monthly' : fields[5] as String,
      postponed: fields[6] == null ? false : fields[6] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, Batch obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.studentClass)
      ..writeByte(3)
      ..write(obj.students)
      ..writeByte(4)
      ..write(obj.defaultFees)
      ..writeByte(5)
      ..write(obj.feesCycle)
      ..writeByte(6)
      ..write(obj.postponed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BatchAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
