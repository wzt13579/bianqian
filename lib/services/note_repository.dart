import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/note.dart';
import 'storage_service.dart';

/// 便签数据访问层（Repository 模式）。
///
/// 屏蔽 Hive 细节，对上提供"业务语义"操作。
class NoteRepository {
  NoteRepository(this._storage);

  final StorageService _storage;
  final Uuid _uuid = const Uuid();

  Box<Note> get _box => _storage.notesBox;

  /// 监听 box 变化，便于 Riverpod StreamProvider。
  Stream<BoxEvent> watch() => _box.watch();

  /// 获取所有未删除便签，按 (置顶优先, 更新时间倒序) 排序。
  List<Note> getAll({bool includeDeleted = false}) {
    final notes = _box.values
        .where((n) => includeDeleted || !n.isDeleted)
        .toList();
    notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updateTime.compareTo(a.updateTime);
    });
    return notes;
  }

  Note? getById(String id) {
    return _box.get(id);
  }

  /// 全文搜索（标题 + 内容 + 标签）。
  List<Note> search(String keyword) {
    if (keyword.trim().isEmpty) return getAll();
    final k = keyword.toLowerCase();
    return getAll().where((n) {
      return n.title.toLowerCase().contains(k) ||
          n.content.toLowerCase().contains(k) ||
          n.tags.any((t) => t.toLowerCase().contains(k));
    }).toList();
  }

  Future<Note> create({
    String title = '',
    String content = '',
    int color = 0xFFFFF8DC,
  }) async {
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: title,
      content: content,
      color: color,
      createTime: now,
      updateTime: now,
    );
    await _box.put(note.id, note);
    return note;
  }

  Future<void> update(Note note) async {
    note.updateTime = DateTime.now();
    await _box.put(note.id, note);
  }

  /// 软删除（移入回收站）。
  Future<void> softDelete(String id) async {
    final note = _box.get(id);
    if (note == null) return;
    note.isDeleted = true;
    note.updateTime = DateTime.now();
    await _box.put(id, note);
  }

  /// 物理删除。
  Future<void> hardDelete(String id) async {
    await _box.delete(id);
  }

  Future<void> togglePin(String id) async {
    final note = _box.get(id);
    if (note == null) return;
    note.isPinned = !note.isPinned;
    note.updateTime = DateTime.now();
    await _box.put(id, note);
  }
}
