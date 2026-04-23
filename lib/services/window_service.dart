import 'dart:io' show Platform;
import 'dart:ui' show Color, Size;

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// 桌面窗口能力封装。
///
/// 提供：无边框、置顶、透明度、贴边隐藏、关闭->最小化到托盘 等能力。
class WindowService {
  WindowService._();
  static final WindowService instance = WindowService._();

  /// 是否启用桌面窗口管理（仅桌面三平台）。
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// 主窗口最大尺寸（与初始尺寸相同；禁止最大化 / 全屏）。
  /// 之所以加上限是因为贴边隐藏依赖于"窗口靠近屏幕边缘"的相对位置，
  /// 一旦窗口被最大化或全屏，就无法判定边缘行为。
  static const Size _maxWindowSize = Size(1040, 650);
  static const Size _minWindowSize = Size(320, 420);

  /// App 启动初始化窗口。请在 `runApp` 之前调用。
  Future<void> ensureInitialized() async {
    if (!_isDesktop) return;

    await windowManager.ensureInitialized();

    const options = WindowOptions(
      size: _maxWindowSize,
      minimumSize: _minWindowSize,
      maximumSize: _maxWindowSize,
      center: true,
      backgroundColor: Color(0x00000000),
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden, // 无边框 / 自定义标题栏
      title: '便签 Bianqian',
      windowButtonVisibility: false,
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      // 双保险：再显式约束一次最大尺寸，并禁用最大化按钮 / 全屏。
      await windowManager.setMinimumSize(_minWindowSize);
      await windowManager.setMaximumSize(_maxWindowSize);
      try {
        await windowManager.setMaximizable(false);
      } catch (_) {/* 旧版 window_manager 没有该方法，忽略 */}
      await windowManager.setFullScreen(false);
      await windowManager.setResizable(true);

      await windowManager.show();
      await windowManager.focus();
      // 阻止系统直接关闭，统一交由我们处理（最小化到托盘）。
      await windowManager.setPreventClose(true);
    });
  }

  /// 切换窗口"始终置顶"。
  Future<bool> toggleAlwaysOnTop() async {
    if (!_isDesktop) return false;
    final current = await windowManager.isAlwaysOnTop();
    await windowManager.setAlwaysOnTop(!current);
    return !current;
  }

  Future<bool> isAlwaysOnTop() async {
    if (!_isDesktop) return false;
    return windowManager.isAlwaysOnTop();
  }

  /// 设置窗口透明度，取值范围 [0.2, 1.0]，避免完全不可见。
  Future<void> setOpacity(double opacity) async {
    if (!_isDesktop) return;
    final v = opacity.clamp(0.2, 1.0);
    await windowManager.setOpacity(v);
  }

  /// 最小化到系统托盘（隐藏窗口）。
  Future<void> hideToTray() async {
    if (!_isDesktop) return;
    await windowManager.hide();
  }

  /// 从托盘恢复显示。
  Future<void> showFromTray() async {
    if (!_isDesktop) return;
    await windowManager.show();
    await windowManager.focus();
  }

  Future<bool> isVisible() async {
    if (!_isDesktop) return true;
    return windowManager.isVisible();
  }

  /// 退出整个应用（绕过 preventClose）。
  Future<void> exitApp() async {
    if (!_isDesktop) return;
    await windowManager.setPreventClose(false);
    await windowManager.destroy();
  }

  // ====== 贴边隐藏（Edge Hide）======
  // 实现思路：当窗口移动到屏幕边缘时，缩成 4px 宽的"侧边条"；
  // 鼠标悬停在边条上时再恢复。完整实现见 [EdgeHideController]。
}
