import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';

import '../models/note.dart';

/// 子窗口（独立便签窗口）专用 —— 通过 IPC 与主窗口通信。
///
/// 因为 `desktop_multi_window` 在 Windows 上是同进程多 Dart isolate，
/// 而 Hive 的 box 文件被主 isolate 持有了排它锁。子 isolate 不能
/// 重复打开同一个 box，否则会抛 `PathAccessException: lock failed`。
///
/// 解决：子窗口完全不接 Hive，所有读写通过 [DesktopMultiWindow.invokeMethod]
/// 路由到主窗口（windowId = 0）的 method handler。
class RemoteNoteService {
  RemoteNoteService._();
  static final RemoteNoteService instance = RemoteNoteService._();

  static const int _mainWindowId = 0;

  /// 拉取一条便签。
  Future<Note?> fetchNote(String id) async {
    final raw = await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'fetchNote',
      id,
    );
    if (raw == null) return null;
    final j = jsonDecode(raw as String) as Map<String, dynamic>;
    return Note.fromJson(j);
  }

  /// 保存一条便签（upsert）。
  Future<void> saveNote(Note note) async {
    await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'saveNote',
      jsonEncode(note.toJson()),
    );
  }

  /// 通知主窗口"重置 isDetached"。
  Future<void> notifyReattach(String noteId) async {
    await DesktopMultiWindow.invokeMethod(
      _mainWindowId,
      'reattach',
      jsonEncode({'noteId': noteId}),
    );
  }
}
