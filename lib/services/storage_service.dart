import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../models/note.dart';
import '../models/note_adapter.dart';

/// Hive 本地存储服务（单例）。
///
/// - 初始化 Hive 存储路径
/// - 注册 [NoteAdapter]
/// - 暴露便签 Box 给上层 Repository / Provider
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const String notesBoxName = 'notes_box';
  static const String settingsBoxName = 'settings_box';

  late final Box<Note> notesBox;
  late final Box<dynamic> settingsBox;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // 桌面平台 hive_flutter.initFlutter 内部会用 path_provider，
    // 但显式指定路径可避免在某些 Windows 环境下默认目录无写权限。
    final dir = await getApplicationSupportDirectory();
    Hive.init(dir.path);

    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(NoteAdapter());
    }

    notesBox = await Hive.openBox<Note>(notesBoxName);
    settingsBox = await Hive.openBox<dynamic>(settingsBoxName);

    _initialized = true;
  }

  Future<void> close() async {
    await Hive.close();
    _initialized = false;
  }

  // ====== 设置项便捷读写 ======
  T? readSetting<T>(String key, {T? defaultValue}) {
    return settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  Future<void> writeSetting<T>(String key, T value) async {
    await settingsBox.put(key, value);
  }
}
