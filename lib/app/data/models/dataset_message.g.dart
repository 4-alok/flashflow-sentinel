// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dataset_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DatasetMessageAdapter extends TypeAdapter<DatasetMessage> {
  @override
  final typeId = 1;

  @override
  DatasetMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DatasetMessage(
      body: fields[0] as String,
      address: fields[1] as String,
      date: fields[2] as DateTime,
      isTransaction: fields[3] == null ? true : fields[3] as bool,
      labels: (fields[4] as Map?)?.cast<String, String>(),
    );
  }

  @override
  void write(BinaryWriter writer, DatasetMessage obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.body)
      ..writeByte(1)
      ..write(obj.address)
      ..writeByte(2)
      ..write(obj.date)
      ..writeByte(3)
      ..write(obj.isTransaction)
      ..writeByte(4)
      ..write(obj.labels);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DatasetMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
