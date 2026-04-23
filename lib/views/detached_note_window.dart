import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/providers.dart';
import '../theme/app_theme.dart';
import 'note_editor_view.dart';

/// 一条便签被"分离"出来后，运行在独立桌面窗口中的根视图。
///
/// 由 [main.dart] 在子窗口模式下挂载。
class DetachedNoteApp extends StatelessWidget {
  const DetachedNoteApp({
    super.key,
    required this.windowId,
    required this.noteId,
  });

  final int windowId;
  final String noteId;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: FluentApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: _DetachedShell(windowId: windowId, noteId: noteId),
      ),
    );
  }
}

class _DetachedShell extends ConsumerWidget {
  const _DetachedShell({required this.windowId, required this.noteId});
  final int windowId;
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteByIdProvider(noteId));
    final color = note != null ? Color(note.color) : Colors.white;

    return Container(
      color: color,
      child: Column(
        children: [
          _DetachedTitleBar(windowId: windowId, noteId: noteId),
          Expanded(
            child: note == null
                ? const Center(child: Text('便签已被删除'))
                : NoteEditorView(noteId: noteId),
          ),
        ],
      ),
    );
  }
}

class _DetachedTitleBar extends ConsumerWidget {
  const _DetachedTitleBar({required this.windowId, required this.noteId});
  final int windowId;
  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = WindowController.fromWindowId(windowId);

    return SizedBox(
      height: 32,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              // 子窗口与主窗口在不同的 FlutterEngine 中，windowManager 单例
              // 在子 Engine 内会绑定到子窗口的原生句柄，因此可直接用于拖拽。
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(FluentIcons.quick_note, size: 12),
                    SizedBox(width: 6),
                    Text('独立便签',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
          ),
          _SmallBtn(
            icon: FluentIcons.pinned,
            tooltip: '置顶',
            onPressed: () async {
              final on = await windowManager.isAlwaysOnTop();
              await windowManager.setAlwaysOnTop(!on);
            },
          ),
          _SmallBtn(
            icon: FluentIcons.back_to_window,
            tooltip: '收回主面板',
            onPressed: () async {
              await DesktopMultiWindow.invokeMethod(
                  0, 'reattach', jsonEncode({'noteId': noteId}));
              await controller.close();
            },
          ),
          _SmallBtn(
            icon: FluentIcons.chrome_close,
            tooltip: '关闭',
            danger: true,
            onPressed: () => controller.close(),
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
  });
  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final btn = SizedBox(
      width: 32,
      height: 32,
      child: HoverButton(
        onPressed: onPressed,
        builder: (ctx, states) {
          Color? bg;
          if (states.isHovered) {
            bg = danger
                ? Colors.red.withValues(alpha: 0.85)
                : Colors.black.withValues(alpha: 0.06);
          }
          final fg = danger && states.isHovered ? Colors.white : null;
          return Container(
            color: bg,
            alignment: Alignment.center,
            child: Icon(icon, size: 12, color: fg),
          );
        },
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
