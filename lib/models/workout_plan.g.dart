// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_plan.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExercisePlanAdapter extends TypeAdapter<ExercisePlan> {
  @override
  final int typeId = 2;

  @override
  ExercisePlan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ExercisePlan(
      name: fields[0] as String,
      exerciseIds: (fields[1] as List).cast<String>(),
      createdAt: fields[2] as DateTime,
      updatedAt: fields[3] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ExercisePlan obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.exerciseIds)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.updatedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExercisePlanAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
