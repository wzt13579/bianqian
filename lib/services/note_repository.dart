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

  // ====== 回收站 ======

  /// 回收站中的便签（仅 isDeleted == true）。
  List<Note> getTrash() {
    final notes = _box.values.where((n) => n.isDeleted).toList();
    notes.sort((a, b) => b.updateTime.compareTo(a.updateTime));
    return notes;
  }

  /// 从回收站恢复。
  Future<void> restore(String id) async {
    final note = _box.get(id);
    if (note == null) return;
    note.isDeleted = false;
    note.updateTime = DateTime.now();
    await _box.put(id, note);
  }

  /// 清空回收站（物理删除所有 isDeleted=true 的便签）。
  Future<int> emptyTrash() async {
    final keys = _box.values.where((n) => n.isDeleted).map((n) => n.id).toList();
    await _box.deleteAll(keys);
    return keys.length;
  }

  // ====== 标签 ======

  /// 所有出现过的标签（去重）按字典序排序。
  List<String> allTags() {
    final s = <String>{};
    for (final n in _box.values) {
      if (n.isDeleted) continue;
      s.addAll(n.tags);
    }
    final list = s.toList()..sort();
    return list;
  }

  /// 按标签筛选便签。
  List<Note> getByTag(String tag) {
    final notes = _box.values
        .where((n) => !n.isDeleted && n.tags.contains(tag))
        .toList();
    notes.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updateTime.compareTo(a.updateTime);
    });
    return notes;
  }

  /// 给便签增加 / 移除标签。
  Future<void> setTags(String id, List<String> tags) async {
    final note = _box.get(id);
    if (note == null) return;
    note.tags = tags.where((t) => t.trim().isNotEmpty).toSet().toList();
    note.updateTime = DateTime.now();
    await _box.put(id, note);
  }

  /// 全局重命名一个标签（影响所有便签）。
  Future<int> renameTag(String oldTag, String newTag) async {
    int affected = 0;
    for (final n in _box.values.toList()) {
      if (n.tags.contains(oldTag)) {
        n.tags = n.tags.map((t) => t == oldTag ? newTag : t).toSet().toList();
        n.updateTime = DateTime.now();
        await _box.put(n.id, n);
        affected++;
      }
    }
    return affected;
  }

  /// 全局删除一个标签。
  Future<int> deleteTag(String tag) async {
    int affected = 0;
    for (final n in _box.values.toList()) {
      if (n.tags.contains(tag)) {
        n.tags = n.tags.where((t) => t != tag).toList();
        n.updateTime = DateTime.now();
        await _box.put(n.id, n);
        affected++;
      }
    }
    return affected;
  }
}
