import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/folder.dart';
import '../models/note.dart';
import 'database.dart';

class NotesRepository {
  Future<Database> get _db async => AppDatabase.instance.database;

  // ----- folders -----

  Future<List<Folder>> listFolders() async {
    final db = await _db;
    final rows = await db.query('folders', orderBy: 'position ASC, id ASC');
    return rows.map(Folder.fromMap).toList();
  }

  Future<Folder> createFolder(String name) async {
    final db = await _db;
    final now = DateTime.now();
    final f = Folder(
      id: 0,
      name: name,
      createdAt: now,
      modifiedAt: now,
    );
    final id = await db.insert('folders', f.toMap());
    return f.copyWith(id: id);
  }

  Future<void> renameFolder(int id, String name) async {
    final db = await _db;
    await db.update(
      'folders',
      {
        'name': name,
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteFolder(int id, {bool moveNotesToRoot = true}) async {
    final db = await _db;
    await db.transaction((txn) async {
      if (moveNotesToRoot) {
        await txn.update(
          'notes',
          {'folder_id': Folder.rootId},
          where: 'folder_id = ?',
          whereArgs: [id],
        );
      } else {
        await txn.update(
          'notes',
          {'is_deleted': 1},
          where: 'folder_id = ?',
          whereArgs: [id],
        );
      }
      await txn.delete('folders', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Map<int, int>> countNotesByFolder() async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT folder_id, COUNT(*) as c FROM notes WHERE is_deleted = 0 GROUP BY folder_id',
    );
    final map = <int, int>{};
    for (final r in rows) {
      map[(r['folder_id'] as int?) ?? 0] = (r['c'] as int?) ?? 0;
    }
    return map;
  }

  // ----- notes -----

  Future<List<Note>> listNotes({
    int? folderId,
    bool includeDeleted = false,
  }) async {
    final db = await _db;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeDeleted) {
      where.add('is_deleted = 0');
    }
    if (folderId != null) {
      where.add('folder_id = ?');
      args.add(folderId);
    }
    final rows = await db.query(
      'notes',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'is_pinned DESC, modified_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<List<Note>> search(String keyword) async {
    final db = await _db;
    final kw = '%${keyword.replaceAll('%', r'\%')}%';
    final rows = await db.query(
      'notes',
      where: 'is_deleted = 0 AND (title LIKE ? ESCAPE ? OR content LIKE ? ESCAPE ?)',
      whereArgs: [kw, r'\', kw, r'\'],
      orderBy: 'modified_at DESC',
    );
    return rows.map(Note.fromMap).toList();
  }

  Future<Note?> findById(int id) async {
    final db = await _db;
    final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Note.fromMap(rows.first);
  }

  Future<Note> upsert(Note note) async {
    final db = await _db;
    if (note.id == 0) {
      final id = await db.insert('notes', note.toMap());
      return note.copyWith(id: id);
    }
    await db.update('notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
    return note;
  }

  Future<void> moveToTrash(int id) async {
    final db = await _db;
    await db.update(
      'notes',
      {
        'is_deleted': 1,
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> moveManyToTrash(List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'notes',
      {
        'is_deleted': 1,
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  Future<void> restore(int id) async {
    final db = await _db;
    await db.update(
      'notes',
      {'is_deleted': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteForever(int id) async {
    final db = await _db;
    await db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> emptyTrash() async {
    final db = await _db;
    await db.delete('notes', where: 'is_deleted = 1');
  }

  Future<void> moveToFolder(List<int> ids, int folderId) async {
    if (ids.isEmpty) return;
    final db = await _db;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.update(
      'notes',
      {
        'folder_id': folderId,
        'modified_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id IN ($placeholders)',
      whereArgs: ids,
    );
  }
}
