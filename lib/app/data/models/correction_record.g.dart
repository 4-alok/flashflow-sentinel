// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'correction_record.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class CorrectionRecordAdapter extends TypeAdapter<CorrectionRecord> {
  @override
  final typeId = 3;

  @override
  CorrectionRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return CorrectionRecord(
      messageKey: fields[0] as String,
      smsBody: fields[1] as String,
      smsAddress: fields[2] as String,
      smsDate: fields[3] as DateTime,
      originalAiJson: fields[4] as String?,
      correctedJson: fields[5] as String,
      reason: fields[6] as String,
      timestamp: fields[7] as DateTime,
      kind: fields[8] as String,
      classifierProbability: (fields[9] as num?)?.toDouble(),
    );
  }

  @override
  void write(BinaryWriter writer, CorrectionRecord obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.messageKey)
      ..writeByte(1)
      ..write(obj.smsBody)
      ..writeByte(2)
      ..write(obj.smsAddress)
      ..writeByte(3)
      ..write(obj.smsDate)
      ..writeByte(4)
      ..write(obj.originalAiJson)
      ..writeByte(5)
      ..write(obj.correctedJson)
      ..writeByte(6)
      ..write(obj.reason)
      ..writeByte(7)
      ..write(obj.timestamp)
      ..writeByte(8)
      ..write(obj.kind)
      ..writeByte(9)
      ..write(obj.classifierProbability);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CorrectionRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
