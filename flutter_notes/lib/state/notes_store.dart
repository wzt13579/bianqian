import 'package:flutter/foundation.dart';

import '../data/notes_repository.dart';
import '../models/folder.dart';
import '../models/note.dart';
import '../services/notification_service.dart';

class NotesStore extends ChangeNotifier {
  NotesStore(this._repo);

  final NotesRepository _repo;

  List<Folder> _folders = [];
  List<Note> _notes = [];
  Map<int, int> _folderCounts = {};
  int _currentFolderId = Folder.rootId; // -2 means "all"
  static const int allFolderId = -2;

  List<Folder> get folders => _folders;
  List<Note> get notes => _notes;
  int get currentFolderId => _currentFolderId;
  Map<int, int> get folderCounts => _folderCounts;

  String currentFolderName() {
    if (_currentFolderId == allFolderId) return '全部便签';
    if (_currentFolderId == Folder.rootId) return '便签';
    final f = _folders.firstWhere(
      (e) => e.id == _currentFolderId,
      orElse: () => Folder(
        id: 0,
        name: '便签',
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      ),
    );
    return f.name;
  }

  Future<void> bootstrap() async {
    await reloadAll();
  }

  Future<void> reloadAll() async {
    _folders = await _repo.listFolders();
    _folderCounts = await _repo.countNotesByFolder();
    await reloadNotes();
  }

  Future<void> reloadNotes() async {
    if (_currentFolderId == allFolderId) {
      _notes = await _repo.listNotes();
    } else {
      _notes = await _repo.listNotes(folderId: _currentFolderId);
    }
    notifyListeners();
  }

  Future<void> setCurrentFolder(int folderId) async {
    _currentFolderId = folderId;
    await reloadNotes();
  }

  // ----- folders -----

  Future<Folder> createFolder(String name) async {
    final f = await _repo.createFolder(name);
    await reloadAll();
    return f;
  }

  Future<void> renameFolder(int id, String name) async {
    await _repo.renameFolder(id, name);
    await reloadAll();
  }

  Future<void> deleteFolder(int id) async {
    await _repo.deleteFolder(id);
    if (_currentFolderId == id) _currentFolderId = Folder.rootId;
    await reloadAll();
  }

  // ----- notes -----

  Future<Note> saveNote(Note note) async {
    final saved = await _repo.upsert(note);
    if (saved.alertAt != null) {
      await NotificationService.instance.schedule(
        id: saved.id,
        title: saved.title.isEmpty ? '便签提醒' : saved.title,
        body: saved.previewText(),
        when: saved.alertAt!,
      );
    } else {
      await NotificationService.instance.cancel(saved.id);
    }
    await reloadAll();
    return saved;
  }

  Future<void> deleteNotes(List<int> ids) async {
    for (final id in ids) {
      await NotificationService.instance.cancel(id);
    }
    await _repo.moveManyToTrash(ids);
    await reloadAll();
  }

  Future<void> moveNotes(List<int> ids, int folderId) async {
    await _repo.moveToFolder(ids, folderId);
    await reloadAll();
  }

  Future<void> togglePin(Note note) async {
    await _repo.upsert(note.copyWith(
      isPinned: !note.isPinned,
      modifiedAt: DateTime.now(),
    ));
    await reloadNotes();
  }

  Future<List<Note>> search(String keyword) => _repo.search(keyword);
}
