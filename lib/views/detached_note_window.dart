import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/note.dart';
import '../services/native_window.dart';
import '../services/remote_note_service.dart';
import '../services/sub_window_edge_hide.dart';

/// 一条便签被"分离"出来后，运行在独立桌面窗口中的根视图。
///
/// 重要：
/// - 不与主窗口共享 Hive，所有读写经由 [RemoteNoteService] -> 主窗口 IPC。
/// - 不调用 `window_manager`，所有窗口控制经由 [WindowController] +
///   [NativeWindow]（win32 ffi）。
class DetachedNoteApp extends StatefulWidget {
  const DetachedNoteApp({
    super.key,
    required this.windowId,
    required this.noteId,
  });

  final int windowId;
  final String noteId;

  @override
  State<DetachedNoteApp> createState() => _DetachedNoteAppState();
}

class _DetachedNoteAppState extends State<DetachedNoteApp> {
  Note? _note;
  bool _loading = true;
  String? _error;
  Timer? _saveTimer;
  bool _isPreview = false;
  bool _isOnTop = false;

  /// 子窗口的原生 HWND（通过 unique title 在启动后定位到）。
  int _hwnd = 0;

  /// 子窗口贴边隐藏（子窗口里 window_manager 不可用，自己用 win32 实现一套）。
  SubWindowEdgeHide? _edgeHide;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  late final WindowController _wc;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _bodyCtrl = TextEditingController();
    _wc = WindowController.fromWindowId(widget.windowId);

    // 1. 先定位 HWND 并修改样式 / 设置图标
    _bootstrapNative();
    // 2. 再去主窗口拉数据
    _load();
  }

  /// 子窗口的 native HWND 锁定 + 样式定制。
  Future<void> _bootstrapNative() async {
    // 启动初期 setTitle('唯一标记') 还在路上，给一点时间让 native 端落地。
    for (int i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final h = NativeWindow.findByTitle(
          '__BIANQIAN_SUBWIN_${widget.noteId}__');
      if (h != 0) {
        _hwnd = h;
        if (kDebugMode) debugPrint('[DetachedWindow] HWND=$h');
        break;
      }
    }
    if (_hwnd == 0) {
      if (kDebugMode) debugPrint('[DetachedWindow] HWND not found, give up');
      return;
    }
    // 去掉最大化按钮 + 禁止边框拉伸
    NativeWindow.removeMaximizeAndResize(_hwnd);
    // 应用主程序图标
    NativeWindow.applyExeIcon(_hwnd);
    // 启动贴边隐藏
    _edgeHide = SubWindowEdgeHide(hwnd: _hwnd)..enable();
    // 同步置顶状态
    if (mounted) {
      setState(() {
        _isOnTop = NativeWindow.isAlwaysOnTop(_hwnd);
      });
    }
  }

  Future<void> _load() async {
    try {
      Note? note;
      // 主窗口 method handler 是 PostFrame 注册的；最多重试几次。
      for (int i = 0; i < 5; i++) {
        try {
          note = await RemoteNoteService.instance.fetchNote(widget.noteId);
          if (note != null) break;
        } catch (e) {
          if (kDebugMode) debugPrint('[DetachedWindow] fetch retry $i: $e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (note == null) {
        setState(() {
          _loading = false;
          _error = '便签不存在或已被删除';
        });
        return;
      }
      _titleCtrl.text = note.title;
      _bodyCtrl.text = note.content;

      // 拿到数据后再把窗口标题改成可读形式
      final readable =
          '便签 - ${note.title.isEmpty ? "(无标题)" : note.title}';
      try {
        await _wc.setTitle(readable);
      } catch (_) {/* ignore */}

      setState(() {
        _note = note;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '加载失败：$e';
      });
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _save);
  }

  Future<void> _save() async {
    final note = _note;
    if (note == null) return;
    note.title = _titleCtrl.text;
    note.content = _bodyCtrl.text;
    note.updateTime = DateTime.now();
    try {
      await RemoteNoteService.instance.saveNote(note);
    } catch (_) {/* 主窗口可能退出了，忽略 */}
  }

  Future<void> _toggleOnTop() async {
    if (_hwnd == 0) return;
    final next = !_isOnTop;
    NativeWindow.setAlwaysOnTop(_hwnd, next);
    setState(() => _isOnTop = next);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _save();
    _edgeHide?.dispose();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(brightness: Brightness.light),
      home: _build(),
    );
  }

  Widget _build() {
    if (_loading) {
      return const ScaffoldPage(
        content: Center(child: ProgressRing()),
      );
    }
    if (_error != null || _note == null) {
      return ScaffoldPage(
        content: Center(
          child: Text(_error ?? '便签不存在', style: const TextStyle(fontSize: 12)),
        ),
      );
    }
    final note = _note!;

    return MouseRegion(
      opaque: false,
      onEnter: (_) => _edgeHide?.onMouseEnter(),
      onExit: (_) => _edgeHide?.onMouseExit(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: Color(note.color),
            child: Column(
            children: [
              _DetachedToolbar(
                isPreview: _isPreview,
                isOnTop: _isOnTop,
                hwnd: _hwnd,
                onTogglePreview: () =>
                    setState(() => _isPreview = !_isPreview),
                onToggleOnTop: _toggleOnTop,
                onReattach: () async {
                  await RemoteNoteService.instance
                      .notifyReattach(widget.noteId);
                  await _wc.close();
                },
                onClose: () => _wc.close(),
              ),
              const Divider(style: DividerThemeData(thickness: 0.5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                child: TextBox(
                  controller: _titleCtrl,
                  placeholder: '标题',
                  unfocusedColor: Colors.transparent,
                  decoration: const WidgetStatePropertyAll(BoxDecoration()),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                  onChanged: (_) => _scheduleSave(),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: _isPreview
                    ? _Preview(text: _bodyCtrl.text)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: TextBox(
                          controller: _bodyCtrl,
                          maxLines: null,
                          expands: true,
                          placeholder: '在这里输入内容…  支持 Markdown',
                          unfocusedColor: Colors.transparent,
                          decoration:
                              const WidgetStatePropertyAll(BoxDecoration()),
                          textAlignVertical: TextAlignVertical.top,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xDE000000),
                            height: 1.5,
                          ),
                          onChanged: (_) => _scheduleSave(),
                        ),
                      ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }
}

/// 子窗口的简易工具条。系统标题栏由 OS 绘制（已通过 win32 去掉最大化），
/// 我们这里只放业务按钮：预览 / 置顶 / 收回 / 关闭。
class _DetachedToolbar extends StatelessWidget {
  const _DetachedToolbar({
    required this.isPreview,
    required this.isOnTop,
    required this.hwnd,
    required this.onTogglePreview,
    required this.onToggleOnTop,
    required this.onReattach,
    required this.onClose,
  });

  final bool isPreview;
  final bool isOnTop;
  final int hwnd;
  final VoidCallback onTogglePreview;
  final VoidCallback onToggleOnTop;
  final VoidCallback onReattach;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          const SizedBox(width: 6),
          _Btn(
            icon: isPreview ? FluentIcons.edit : FluentIcons.preview,
            tooltip: isPreview ? '回到编辑' : 'Markdown 预览',
            onPressed: onTogglePreview,
          ),
          _Btn(
            icon: FluentIcons.pinned,
            tooltip: isOnTop ? '取消置顶' : '置顶',
            active: isOnTop,
            onPressed: onToggleOnTop,
          ),
          const Spacer(),
          _Btn(
            icon: FluentIcons.back_to_window,
            tooltip: '收回主面板',
            onPressed: onReattach,
          ),
          _Btn(
            icon: FluentIcons.chrome_close,
            tooltip: '关闭',
            danger: true,
            onPressed: onClose,
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  const _Btn({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool danger;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: 28,
      height: 28,
      child: HoverButton(
        onPressed: onPressed,
        builder: (ctx, states) {
          Color? bg = active ? Colors.black.withValues(alpha: 0.08) : null;
          if (states.isHovered) {
            bg = danger
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.black.withValues(alpha: 0.10);
          }
          final fg = danger && states.isHovered ? Colors.white : null;
          return Container(
            decoration:
                BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
            alignment: Alignment.center,
            child: Icon(icon, size: 13, color: fg),
          );
        },
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const Center(
        child: Text('（暂无内容）',
            style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
      );
    }
    return Markdown(
      data: text,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 13, color: Colors.black, height: 1.55),
        h1: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black),
        h2: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
        h3: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black),
      ),
      checkboxBuilder: (checked) => Padding(
        padding: const EdgeInsets.only(right: 4, top: 2),
        child: Icon(
          checked ? FluentIcons.checkbox_composite : FluentIcons.checkbox,
          size: 13,
          color: Colors.black,
        ),
      ),
    );
  }
}
