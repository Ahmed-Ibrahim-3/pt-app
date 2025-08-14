// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_plan_assignment.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PlanAssignmentAdapter extends TypeAdapter<PlanAssignment> {
  @override
  final int typeId = 3;

  @override
  PlanAssignment read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlanAssignment(
      date: fields[0] as DateTime,
      planKey: fields[1] as int,
      completed: fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, PlanAssignment obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.planKey)
      ..writeByte(2)
      ..write(obj.completed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanAssignmentAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
