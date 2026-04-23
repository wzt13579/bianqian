import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../services/note_repository.dart';
import '../services/storage_service.dart';
import '../services/window_service.dart';

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

// =====================  UI 状态 Provider  =====================

/// 搜索关键词。
final searchKeywordProvider = StateProvider<String>((ref) => '');

/// 当前选中便签 id。
final selectedNoteIdProvider = StateProvider<String?>((ref) => null);

/// 窗口透明度（0.2 ~ 1.0）。
final windowOpacityProvider = StateProvider<double>((ref) => 1.0);

/// 是否置顶。
final alwaysOnTopProvider = StateProvider<bool>((ref) => false);

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

/// 经搜索过滤后的便签列表。
final filteredNotesProvider = Provider<List<Note>>((ref) {
  ref.watch(notesRevisionProvider); // 数据变更触发刷新
  final repo = ref.watch(noteRepositoryProvider);
  final keyword = ref.watch(searchKeywordProvider);
  return keyword.isEmpty ? repo.getAll() : repo.search(keyword);
});

/// 单条便签。
final noteByIdProvider = Provider.family<Note?, String>((ref, id) {
  ref.watch(notesRevisionProvider);
  return ref.watch(noteRepositoryProvider).getById(id);
});
