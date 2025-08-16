// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workout_session.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class WorkoutSessionAdapter extends TypeAdapter<WorkoutSession> {
  @override
  final int typeId = 4;

  @override
  WorkoutSession read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkoutSession(
      date: fields[0] as DateTime,
      planKey: fields[1] as int,
      entries: (fields[2] as List).cast<WorkoutEntry>(),
      startedAt: fields[3] as DateTime,
      finishedAt: fields[4] as DateTime?,
      completed: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, WorkoutSession obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.date)
      ..writeByte(1)
      ..write(obj.planKey)
      ..writeByte(2)
      ..write(obj.entries)
      ..writeByte(3)
      ..write(obj.startedAt)
      ..writeByte(4)
      ..write(obj.finishedAt)
      ..writeByte(5)
      ..write(obj.completed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutSessionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class WorkoutEntryAdapter extends TypeAdapter<WorkoutEntry> {
  @override
  final int typeId = 5;

  @override
  WorkoutEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return WorkoutEntry(
      exerciseStableId: fields[0] as String,
      sets: (fields[1] as List).cast<SetEntry>(),
      done: fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, WorkoutEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.exerciseStableId)
      ..writeByte(1)
      ..write(obj.sets)
      ..writeByte(2)
      ..write(obj.done);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WorkoutEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class SetEntryAdapter extends TypeAdapter<SetEntry> {
  @override
  final int typeId = 6;

  @override
  SetEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SetEntry(
      reps: fields[0] as int,
      weight: fields[1] as double,
      done: fields[2] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SetEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.reps)
      ..writeByte(1)
      ..write(obj.weight)
      ..writeByte(2)
      ..write(obj.done);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
