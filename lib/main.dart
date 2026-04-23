import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'providers/providers.dart';
import 'services/storage_service.dart';
import 'services/tray_service.dart';
import 'services/window_service.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1) 本地存储 Hive
  await StorageService.instance.init();

  // 2) 桌面窗口（无边框 / 自定义标题栏 / 阻止关闭）
  await WindowService.instance.ensureInitialized();

  // 3) 系统托盘
  await TrayService.instance.init();

  runApp(const ProviderScope(child: BianqianApp()));
}

class BianqianApp extends ConsumerWidget {
  const BianqianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

/// 监听窗口"关闭"事件 -> 隐藏到托盘（而不是退出）。
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
