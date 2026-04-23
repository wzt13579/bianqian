import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/providers.dart';
import 'services/edge_hide_service.dart';
import 'services/multi_window_service.dart';
import 'services/storage_service.dart';
import 'services/tray_service.dart';
import 'services/window_service.dart';
import 'theme/app_theme.dart';
import 'views/detached_note_window.dart';
import 'views/home_view.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ============== 子窗口模式（便签分离窗口）==============
  // desktop_multi_window 在子窗口启动时会带 args:
  //   args[0] == 'multi_window'
  //   args[1] == windowId
  //   args[2] == jsonEncoded user arguments
  if (args.isNotEmpty && args.first == 'multi_window') {
    final windowId = int.parse(args[1]);
    final argument = args.length > 2
        ? jsonDecode(args[2]) as Map<String, dynamic>
        : <String, dynamic>{};

    // ⚠️ 子窗口里千万不要：
    //   1) 调用 StorageService.init() —— Hive 文件锁会和主 isolate 冲突
    //   2) 调用 windowManager.ensureInitialized() —— window_manager 的
    //      native 端是进程单例，从子 isolate 调用会路由到主窗口的句柄，
    //      甚至阻塞子 isolate（从而 runApp 都不会执行 → 子窗口空白）。
    //
    // 子窗口需要的窗口控制走 win32 ffi（NativeWindow），数据走 IPC（RemoteNoteService）。

    final mode = argument['mode'] as String?;
    if (mode == 'detached_note') {
      final noteId = argument['noteId'] as String;
      runApp(DetachedNoteApp(windowId: windowId, noteId: noteId));
      return;
    }
    return;
  }

  // ============== 主窗口模式 ==============
  await StorageService.instance.init();
  await WindowService.instance.ensureInitialized();
  await TrayService.instance.init();

  // 启用贴边隐藏
  EdgeHideService.instance.enable();

  runApp(const ProviderScope(child: BianqianApp()));
}

class BianqianApp extends ConsumerStatefulWidget {
  const BianqianApp({super.key});

  @override
  ConsumerState<BianqianApp> createState() => _BianqianAppState();
}

class _BianqianAppState extends ConsumerState<BianqianApp> {
  @override
  void initState() {
    super.initState();
    // 注册"子窗口 -> 主窗口"消息处理（取消分离 / 关闭通知）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final repo = ref.read(noteRepositoryProvider);
      MultiWindowService.instance.registerMethodHandler(repo);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: '便签 Bianqian',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const _AppShell(),
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN):
            const _NewNoteIntent(),
      },
      actions: <Type, Action<Intent>>{
        _NewNoteIntent: _NewNoteAction(ref),
      },
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell();

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> with WindowListener {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (!kIsWeb) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final isPrevented = await windowManager.isPreventClose();
    if (isPrevented) {
      await WindowService.instance.hideToTray();
    }
  }

  /// 窗口拖动结束时再判定贴边（避免拖动过程中频繁误判）。
  @override
  void onWindowMoved() => EdgeHideService.instance.onWindowMoved();

  @override
  void onWindowResized() => EdgeHideService.instance.onWindowMoved();

  /// 取消置顶 / 失焦后窗口可能被拖离边缘 —— 也重新判定一次。
  @override
  void onWindowFocus() => EdgeHideService.instance.onWindowMoved();

  @override
  Widget build(BuildContext context) => const HomeView();
}

class _NewNoteIntent extends Intent {
  const _NewNoteIntent();
}

class _NewNoteAction extends Action<_NewNoteIntent> {
  _NewNoteAction(this.ref);
  final WidgetRef ref;

  @override
  Object? invoke(_NewNoteIntent intent) async {
    final repo = ref.read(noteRepositoryProvider);
    final note = await repo.create();
    ref.read(selectedNoteIdProvider.notifier).state = note.id;
    return null;
  }
}
