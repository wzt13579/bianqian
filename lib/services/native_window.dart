import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// 直接走 Win32 API 控制子窗口（HWND）。
///
/// 之所以需要这一层：`window_manager` 的 native 端是进程单例，从子 isolate
/// 调用会路由到主窗口的 HWND（甚至会阻塞子 isolate），导致独立便签窗口
/// 既无法设置自身样式，也起不来 Flutter 内容。
///
/// 因此独立窗口的 "去掉最大化按钮 / 设置图标 / 拖动 / 置顶" 全部走 Win32。
class NativeWindow {
  NativeWindow._();

  /// 通过窗口标题精确查找 HWND（标题需保证唯一）。
  static int findByTitle(String title) {
    final p = title.toNativeUtf16();
    try {
      return FindWindow(nullptr, p);
    } finally {
      calloc.free(p);
    }
  }

  /// 修改窗口标题（HWND 已知）。
  static void setTitle(int hwnd, String title) {
    if (hwnd == 0) return;
    final p = title.toNativeUtf16();
    try {
      SetWindowText(hwnd, p);
    } finally {
      calloc.free(p);
    }
  }

  /// 去掉"最大化按钮"和"边框拉伸"。窗口仍可移动 / 关闭 / 最小化。
  static void removeMaximizeAndResize(int hwnd) {
    if (hwnd == 0) return;
    final style = GetWindowLongPtr(hwnd, GWL_STYLE);
    final newStyle = style & ~WS_MAXIMIZEBOX & ~WS_THICKFRAME;
    SetWindowLongPtr(hwnd, GWL_STYLE, newStyle);
    SetWindowPos(
      hwnd,
      0,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED,
    );
  }

  /// 设置窗口置顶 / 取消置顶。
  static void setAlwaysOnTop(int hwnd, bool on) {
    if (hwnd == 0) return;
    SetWindowPos(
      hwnd,
      on ? HWND_TOPMOST : HWND_NOTOPMOST,
      0,
      0,
      0,
      0,
      SWP_NOMOVE | SWP_NOSIZE,
    );
  }

  /// 查询窗口是否处于置顶状态。
  static bool isAlwaysOnTop(int hwnd) {
    if (hwnd == 0) return false;
    final ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    return (ex & WS_EX_TOPMOST) != 0;
  }

  /// 在自定义标题栏上"按下鼠标"时调用，触发系统级窗口拖动。
  static void startDragging(int hwnd) {
    if (hwnd == 0) return;
    ReleaseCapture();
    SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
  }

  /// 把当前主可执行文件中嵌入的图标（windows/runner/resources/app_icon.ico
  /// 通过 Runner.rc 编译进 exe，资源 ID = IDI_APP_ICON = 101）
  /// 赋给指定 HWND（标题栏左上角 + 任务栏）。
  static void applyExeIcon(int hwnd) {
    if (hwnd == 0) return;
    // MAKEINTRESOURCE(101)：把整数资源 ID 当作 UTF16 指针使用是 Win32 惯用法。
    final hModule = GetModuleHandle(nullptr);
    final hIcon = LoadIcon(hModule, Pointer<Utf16>.fromAddress(101));
    if (hIcon != 0) {
      SendMessage(hwnd, WM_SETICON, ICON_SMALL, hIcon);
      SendMessage(hwnd, WM_SETICON, ICON_BIG, hIcon);
    }
  }

  /// 关闭窗口（兜底）。
  static void close(int hwnd) {
    if (hwnd == 0) return;
    PostMessage(hwnd, WM_CLOSE, 0, 0);
  }
}
