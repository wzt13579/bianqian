import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../services/multi_window_service.dart';
import '../services/note_repository.dart';
import '../services/storage_service.dart';
import '../services/window_service.dart';

/// 主界面左侧导航模式。
enum NavMode { allNotes, tag, trash }

/// 当前导航选择。
class NavSelection {
  const NavSelection(this.mode, [this.tag]);
  final NavMode mode;
  final String? tag;

  static const NavSelection all = NavSelection(NavMode.allNotes);
  static const NavSelection trash = NavSelection(NavMode.trash);
  factory NavSelection.byTag(String tag) => NavSelection(NavMode.tag, tag);
}

// =====================  服务层 Provider  =====================

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  return NoteRepository(ref.watch(storageServiceProvider));
});

final windowServiceProvider = Provider<WindowService>((ref) {
  return WindowService.instance;
});

final multiWindowServiceProvider = Provider<MultiWindowService>((ref) {
  return MultiWindowService.instance;
});

// =====================  UI 状态 Provider  =====================

/// 搜索关键词。
final searchKeywordProvider = StateProvider<String>((ref) => '');

/// 当前选中便签 id。
final selectedNoteIdProvider = StateProvider<String?>((ref) => null);

/// 窗口透明度（0.2 ~ 1.0）。
final windowOpacityProvider = StateProvider<double>((ref) => 1.0);

/// 是否置顶。
final alwaysOnTopProvider = StateProvider<bool>((ref) => false);

/// 当前导航选择。
final navSelectionProvider =
    StateProvider<NavSelection>((ref) => NavSelection.all);

// =====================  数据流 Provider  =====================

/// 监听 Hive Box 变化的"版本号"，每次变化 +1，用于触发 [filteredNotesProvider]。
final notesRevisionProvider = StreamProvider<int>((ref) async* {
  final repo = ref.watch(noteRepositoryProvider);
  int rev = 0;
  yield rev;
  await for (final _ in repo.watch()) {
    yield ++rev;
  }
});

/// 经搜索 + 导航筛选后的便签列表。
final filteredNotesProvider = Provider<List<Note>>((ref) {
  ref.watch(notesRevisionProvider);
  final repo = ref.watch(noteRepositoryProvider);
  final keyword = ref.watch(searchKeywordProvider).toLowerCase();
  final nav = ref.watch(navSelectionProvider);

  List<Note> base;
  switch (nav.mode) {
    case NavMode.allNotes:
      base = repo.getAll();
      break;
    case NavMode.tag:
      base = nav.tag == null ? repo.getAll() : repo.getByTag(nav.tag!);
      break;
    case NavMode.trash:
      base = repo.getTrash();
      break;
  }

  if (keyword.isEmpty) return base;
  return base.where((n) {
    return n.title.toLowerCase().contains(keyword) ||
        n.content.toLowerCase().contains(keyword) ||
        n.tags.any((t) => t.toLowerCase().contains(keyword));
  }).toList();
});

/// 全部标签。
final allTagsProvider = Provider<List<String>>((ref) {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).allTags();
});

/// 回收站项数（用于导航徽标）。
final trashCountProvider = Provider<int>((ref) {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).getTrash().length;
});

/// 单条便签。
final noteByIdProvider = Provider.family<Note?, String>((ref, id) {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).getById(id);
});
