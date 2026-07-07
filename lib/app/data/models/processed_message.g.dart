// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'processed_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProcessedMessageAdapter extends TypeAdapter<ProcessedMessage> {
  @override
  final typeId = 2;

  @override
  ProcessedMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProcessedMessage(
      msgKey: fields[0] as String,
      body: fields[1] as String,
      address: fields[2] as String,
      smsDate: fields[3] as DateTime,
      classifiedAsTransaction: fields[4] as bool,
      classifierProbability: (fields[5] as num).toDouble(),
      extractionStatus: fields[6] as String,
      rawLlmOutput: fields[7] as String?,
      extractionAttempts: fields[8] == null ? 0 : (fields[8] as num).toInt(),
      aiType: fields[9] as String?,
      aiAmount: (fields[10] as num?)?.toDouble(),
      aiDate: fields[11] as DateTime?,
      aiVendor: fields[12] as String?,
      aiBank: fields[13] as String?,
      aiAccount: fields[14] as String?,
      aiBalance: (fields[15] as num?)?.toDouble(),
      aiReferenceId: fields[16] as String?,
      aiCurrency: fields[17] as String?,
      overrideType: fields[18] as String?,
      overrideAmount: (fields[19] as num?)?.toDouble(),
      overrideVendor: fields[20] as String?,
      overrideDate: fields[21] as DateTime?,
      excluded: fields[22] == null ? false : fields[22] as bool,
      overrideReason: fields[23] as String?,
      overriddenAt: fields[24] as DateTime?,
      userSaysTransaction: fields[25] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, ProcessedMessage obj) {
    writer
      ..writeByte(26)
      ..writeByte(0)
      ..write(obj.msgKey)
      ..writeByte(1)
      ..write(obj.body)
      ..writeByte(2)
      ..write(obj.address)
      ..writeByte(3)
      ..write(obj.smsDate)
      ..writeByte(4)
      ..write(obj.classifiedAsTransaction)
      ..writeByte(5)
      ..write(obj.classifierProbability)
      ..writeByte(6)
      ..write(obj.extractionStatus)
      ..writeByte(7)
      ..write(obj.rawLlmOutput)
      ..writeByte(8)
      ..write(obj.extractionAttempts)
      ..writeByte(9)
      ..write(obj.aiType)
      ..writeByte(10)
      ..write(obj.aiAmount)
      ..writeByte(11)
      ..write(obj.aiDate)
      ..writeByte(12)
      ..write(obj.aiVendor)
      ..writeByte(13)
      ..write(obj.aiBank)
      ..writeByte(14)
      ..write(obj.aiAccount)
      ..writeByte(15)
      ..write(obj.aiBalance)
      ..writeByte(16)
      ..write(obj.aiReferenceId)
      ..writeByte(17)
      ..write(obj.aiCurrency)
      ..writeByte(18)
      ..write(obj.overrideType)
      ..writeByte(19)
      ..write(obj.overrideAmount)
      ..writeByte(20)
      ..write(obj.overrideVendor)
      ..writeByte(21)
      ..write(obj.overrideDate)
      ..writeByte(22)
      ..write(obj.excluded)
      ..writeByte(23)
      ..write(obj.overrideReason)
      ..writeByte(24)
      ..write(obj.overriddenAt)
      ..writeByte(25)
      ..write(obj.userSaysTransaction);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProcessedMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
