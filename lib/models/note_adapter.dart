import 'package:hive/hive.dart';

import 'note.dart';

/// 手写的 Hive [TypeAdapter] —— 等同于 `hive_generator` 自动生成的产物。
///
/// 目的：避免开发期必须先运行 build_runner 才能编译运行。
class NoteAdapter extends TypeAdapter<Note> {
  @override
  final int typeId = 0;

  @override
  Note read(BinaryReader reader) {
    final fieldsCount = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < fieldsCount; i++) reader.readByte(): reader.read(),
    };
    return Note(
      id: fields[0] as String,
      title: (fields[1] as String?) ?? '',
      content: (fields[2] as String?) ?? '',
      color: (fields[3] as int?) ?? 0xFFFFF8DC,
      isPinned: (fields[4] as bool?) ?? false,
      reminderTime: fields[5] as DateTime?,
      createTime: fields[6] as DateTime,
      updateTime: fields[7] as DateTime,
      tags: (fields[8] as List?)?.cast<String>() ?? <String>[],
      isDeleted: (fields[9] as bool?) ?? false,
      isDetached: (fields[10] as bool?) ?? false,
      // 字段 11 在老版本数据中可能不存在，这里安全默认为 0
      sortIndex: (fields[11] as int?) ?? 0,
    );
  }

  @override
  void write(BinaryWriter writer, Note obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.content)
      ..writeByte(3)
      ..write(obj.color)
      ..writeByte(4)
      ..write(obj.isPinned)
      ..writeByte(5)
      ..write(obj.reminderTime)
      ..writeByte(6)
      ..write(obj.createTime)
      ..writeByte(7)
      ..write(obj.updateTime)
      ..writeByte(8)
      ..write(obj.tags)
      ..writeByte(9)
      ..write(obj.isDeleted)
      ..writeByte(10)
      ..write(obj.isDetached)
      ..writeByte(11)
      ..write(obj.sortIndex);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NoteAdapter && other.typeId == typeId;
}
