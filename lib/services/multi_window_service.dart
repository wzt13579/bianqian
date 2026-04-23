import 'dart:convert';
import 'dart:ui' show Rect;

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'note_repository.dart';

/// 多窗口（便签分离）管理。
///
/// - 主窗口通过 [detachNote] 创建独立子窗口；
/// - 子窗口通过 invokeMethod('reattach') 通知主窗口取消分离状态；
/// - 主窗口在 [registerMethodHandler] 中接收子窗口消息。
class MultiWindowService {
  MultiWindowService._();
  static final MultiWindowService instance = MultiWindowService._();

  /// 已分离的子窗口：noteId -> windowId。
  final Map<String, int> _detachedWindows = <String, int>{};

  /// 在主窗口中调用：注册子窗口的回调通道。
  ///
  /// 子窗口通过 [DesktopMultiWindow.invokeMethod(0, ...)] 调用以下方法：
  /// - `fetchNote`：args = noteId(String)，返回 jsonEncode(Note) 或 null
  /// - `saveNote`：args = jsonEncode(Note)，upsert 到 Hive
  /// - `reattach`：args = {noteId}，清除分离状态
  void registerMethodHandler(NoteRepository repo) {
    DesktopMultiWindow.setMethodHandler((call, fromWindowId) async {
      switch (call.method) {
        case 'fetchNote':
          final id = call.arguments as String;
          final note = repo.getById(id);
          return note == null ? null : jsonEncode(note.toJson());

        case 'saveNote':
          final j = jsonDecode(call.arguments as String) as Map<String, dynamic>;
          final note = Note.fromJson(j);
          await repo.upsertRaw(note);
          return true;

        case 'reattach':
          final args = jsonDecode(call.arguments as String) as Map;
          final noteId = args['noteId'] as String;
          _detachedWindows.remove(noteId);
          final note = repo.getById(noteId);
          if (note != null) {
            note.isDetached = false;
            await repo.update(note);
          }
          return true;

        case 'closed':
          final args = jsonDecode(call.arguments as String) as Map;
          final noteId = args['noteId'] as String;
          _detachedWindows.remove(noteId);
          return true;
      }
      return null;
    });
  }

  /// 主窗口调用：把一条便签"分离"为独立桌面窗口。
  Future<void> detachNote(Note note, NoteRepository repo) async {
    if (_detachedWindows.containsKey(note.id)) {
      // 已分离 -> 直接聚焦该窗口
      final wid = _detachedWindows[note.id]!;
      await WindowController.fromWindowId(wid).show();
      return;
    }

    // 子窗口标题分两步：
    //   1) 先设一个唯一标识（包含 noteId），子窗口启动后通过 FindWindow 找到
    //      自己的 HWND 修改样式 / 设置图标；
    //   2) 子窗口稳定后再把标题改为可读的"便签 - xxx"。
    final uniqueTag = '__BIANQIAN_SUBWIN_${note.id}__';
    final args = jsonEncode({
      'mode': 'detached_note',
      'noteId': note.id,
      'uniqueTag': uniqueTag,
    });

    final window = await DesktopMultiWindow.createWindow(args);
    await window.setFrame(const Rect.fromLTWH(120, 120, 360, 480));
    await window.setTitle(uniqueTag);
    await window.show();

    _detachedWindows[note.id] = window.windowId;

    note.isDetached = true;
    await repo.update(note);

    if (kDebugMode) {
      debugPrint('Detached note ${note.id} -> window ${window.windowId}');
    }
  }
}
