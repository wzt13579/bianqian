import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

import 'window_service.dart';

/// 系统托盘服务。
///
/// 负责：注册托盘图标、托盘菜单、点击事件路由到 [WindowService]。
class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> init() async {
    if (!_isDesktop) return;

    // 注意：图标资源文件需放在 assets/icons/ 下，详见 README。
    // Windows 下推荐 .ico；macOS 推荐 16x16 .png。
    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/icons/tray.ico'
            : 'assets/icons/tray.png',
      );
    } catch (_) {
      // 图标缺失时静默忽略，不阻塞启动。
    }

    await trayManager.setToolTip('便签 Bianqian');
    await _setMenu();

    trayManager.addListener(this);
  }

  Future<void> _setMenu() async {
    final menu = Menu(items: [
      MenuItem(key: 'show', label: '打开主面板'),
      MenuItem(key: 'new_note', label: '新建便签'),
      MenuItem.separator(),
      MenuItem.checkbox(
        key: 'always_on_top',
        label: '窗口置顶',
        checked: await WindowService.instance.isAlwaysOnTop(),
      ),
      MenuItem.separator(),
      MenuItem(key: 'quit', label: '退出'),
    ]);
    await trayManager.setContextMenu(menu);
  }

  @override
  void onTrayIconMouseDown() {
    WindowService.instance.showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await WindowService.instance.showFromTray();
        break;
      case 'new_note':
        await WindowService.instance.showFromTray();
        // TODO: 通过全局 ProviderContainer 触发新建便签
        break;
      case 'always_on_top':
        await WindowService.instance.toggleAlwaysOnTop();
        await _setMenu();
        break;
      case 'quit':
        await WindowService.instance.exitApp();
        break;
    }
  }

  Future<void> dispose() async {
    trayManager.removeListener(this);
    await trayManager.destroy();
  }
}
