import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// 贴边隐藏（参考 QQ 桌面客户端的体验）：
///
/// 状态机：
/// ```
///                                ┌──── 鼠标离开 + 700ms ────┐
///                                ▼                          │
///   free  ──拖到屏幕边缘──▶  docked  ─────▶ 滑出动画 ─────▶ hidden
///                                ▲                          │
///                                └──── 鼠标进入 5px ◀──── 滑入动画
/// ```
///
/// 关键点：
/// - **不改变窗口大小**，只改变窗口位置（把窗口推出屏幕，留 5px peek）。
/// - 滑入/滑出带 ~180ms 缓动动画。
/// - 任意时刻都可以贴边隐藏（不强制要求置顶）。隐藏期间会临时把窗口置顶
///   以保证 peek 条不被其他窗口遮住。
enum HideSide { none, top, left, right }

enum DockState {
  /// 自由状态，未贴边。
  free,

  /// 已贴边但完整可见（鼠标在窗口内）。
  docked,

  /// 已滑出，仅露出 5px peek 条（鼠标在窗口外）。
  hidden,
}

class EdgeHideService {
  EdgeHideService._();
  static final EdgeHideService instance = EdgeHideService._();

  // ============== 配置 ==============

  /// 触发贴边的最大像素距离（窗口边距屏幕边 ≤ 此值即"贴边"）。
  static const double snapThreshold = 8.0;

  /// 隐藏后保留在屏幕内的露出像素（用于鼠标 peek）。
  static const double peekSize = 5.0;

  /// 鼠标离开窗口后多久自动滑出。
  static const Duration autoHideDelay = Duration(milliseconds: 700);

  /// 滑入/滑出动画时长。
  static const Duration animationDuration = Duration(milliseconds: 180);
  static const int _animationFrames = 14;

  // ============== 内部状态 ==============

  bool _enabled = false;
  bool _animating = false;

  HideSide _side = HideSide.none;
  DockState _state = DockState.free;

  /// docked 状态下的窗口 frame（完整可见）。
  Rect? _dockedFrame;

  /// hidden 状态下的窗口 frame（推出屏幕，仅留 peek）。
  Rect? _hiddenFrame;

  Timer? _hideTimer;

  /// hidden 期间是否被本服务"临时置顶"了。restore 时需要回退。
  bool _tempOnTop = false;

  HideSide get side => _side;
  DockState get state => _state;

  final StreamController<DockState> _stateCtrl =
      StreamController<DockState>.broadcast();
  Stream<DockState> get stateStream => _stateCtrl.stream;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void enable() {
    _enabled = _isDesktop;
    if (_enabled) {
      // 启动时窗口可能就已经在屏幕边缘 —— 主动检测一次。
      Future<void>.delayed(const Duration(milliseconds: 800), onWindowMoved);
    }
  }

  void disable() {
    _enabled = false;
    _hideTimer?.cancel();
  }

  // ============== 由 WindowListener 调用 ==============

  /// 由 [WindowListener.onWindowMove]/[onWindowResize] 调用。
  Future<void> onWindowMoved() async {
    if (!_enabled || _animating) return;
    // 隐藏态时窗口位置由我们驱动，不响应位移
    if (_state == DockState.hidden) return;

    final display = await screenRetriever.getPrimaryDisplay();
    final pos = await windowManager.getPosition();
    final size = await windowManager.getSize();
    final screen = display.size;

    final near = _detectEdge(pos, size, screen);
    if (near == HideSide.none) {
      if (_state == DockState.docked) await _setState(DockState.free);
      _side = HideSide.none;
      _dockedFrame = null;
      _hiddenFrame = null;
      return;
    }

    // 进入 docked 状态：把窗口"贴齐"到屏幕边缘（防止有 1~2px 缝隙）。
    final docked = _alignToEdge(near, pos, size, screen);
    _side = near;
    _dockedFrame = docked;
    _hiddenFrame = _hiddenFrameFor(near, docked, screen);

    if (_state != DockState.docked) {
      await _setState(DockState.docked);
    }

    // 贴齐窗口位置（仅当当前位置和理想 docked 位置不一致才动）
    if ((pos.dx - docked.left).abs() > 0.5 ||
        (pos.dy - docked.top).abs() > 0.5) {
      await windowManager.setPosition(docked.topLeft);
    }
  }

  // ============== 由 EdgeHideOverlay (UI) 调用 ==============

  /// 鼠标进入窗口：取消滑出计时；若当前已隐藏则滑入。
  Future<void> onMouseEnter() async {
    if (!_enabled || _side == HideSide.none) return;
    _hideTimer?.cancel();
    if (_state == DockState.hidden) {
      await _slideIn();
    }
  }

  /// 鼠标离开窗口：在 docked 状态下安排"延迟滑出"。
  Future<void> onMouseExit() async {
    if (!_enabled || _side == HideSide.none) return;
    _hideTimer?.cancel();
    if (_state == DockState.docked) {
      _hideTimer = Timer(autoHideDelay, () async {
        // 再次确认仍在 docked 状态（用户没把窗口拖走）
        if (_state == DockState.docked) {
          await _slideOut();
        }
      });
    }
  }

  // ============== 内部：边缘判定 / 滑动动画 ==============

  HideSide _detectEdge(Offset pos, Size size, Size screen) {
    if (pos.dy <= snapThreshold) return HideSide.top;
    if (pos.dx <= snapThreshold) return HideSide.left;
    if (pos.dx + size.width >= screen.width - snapThreshold) {
      return HideSide.right;
    }
    return HideSide.none;
  }

  Rect _alignToEdge(HideSide side, Offset pos, Size size, Size screen) {
    switch (side) {
      case HideSide.top:
        return Rect.fromLTWH(pos.dx, 0, size.width, size.height);
      case HideSide.left:
        return Rect.fromLTWH(0, pos.dy, size.width, size.height);
      case HideSide.right:
        return Rect.fromLTWH(
            screen.width - size.width, pos.dy, size.width, size.height);
      case HideSide.none:
        return Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
    }
  }

  /// 计算"隐藏后"的窗口 frame：把窗口推出屏幕，仅留 peekSize 像素。
  Rect _hiddenFrameFor(HideSide side, Rect docked, Size screen) {
    switch (side) {
      case HideSide.top:
        return Rect.fromLTWH(
          docked.left,
          -(docked.height - peekSize),
          docked.width,
          docked.height,
        );
      case HideSide.left:
        return Rect.fromLTWH(
          -(docked.width - peekSize),
          docked.top,
          docked.width,
          docked.height,
        );
      case HideSide.right:
        return Rect.fromLTWH(
          screen.width - peekSize,
          docked.top,
          docked.width,
          docked.height,
        );
      case HideSide.none:
        return docked;
    }
  }

  Future<void> _slideOut() async {
    final from = _dockedFrame;
    final to = _hiddenFrame;
    if (from == null || to == null) return;
    // 隐藏前临时置顶，避免 5px peek 条被其他窗口盖住。
    final wasOnTop = await windowManager.isAlwaysOnTop();
    if (!wasOnTop) {
      await windowManager.setAlwaysOnTop(true);
      _tempOnTop = true;
    }
    await _animatePosition(from.topLeft, to.topLeft);
    await _setState(DockState.hidden);
  }

  Future<void> _slideIn() async {
    final from = _hiddenFrame;
    final to = _dockedFrame;
    if (from == null || to == null) return;
    await _animatePosition(from.topLeft, to.topLeft);
    // 恢复用户原本的置顶状态
    if (_tempOnTop) {
      await windowManager.setAlwaysOnTop(false);
      _tempOnTop = false;
    }
    await _setState(DockState.docked);
  }

  Future<void> _animatePosition(Offset from, Offset to) async {
    _animating = true;
    try {
      final stepMs =
          (animationDuration.inMilliseconds / _animationFrames).round();
      for (int i = 1; i <= _animationFrames; i++) {
        final t = _easeOut(i / _animationFrames);
        final pos = Offset(
          from.dx + (to.dx - from.dx) * t,
          from.dy + (to.dy - from.dy) * t,
        );
        await windowManager.setPosition(pos);
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
      // 收尾对齐
      await windowManager.setPosition(to);
    } finally {
      _animating = false;
    }
  }

  /// easeOutCubic
  double _easeOut(double t) {
    final inv = 1 - t;
    return 1 - math.pow(inv, 3).toDouble();
  }

  Future<void> _setState(DockState s) async {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
    if (kDebugMode) debugPrint('[EdgeHide] state -> $s, side=$_side');
  }

  void dispose() {
    _hideTimer?.cancel();
    _stateCtrl.close();
  }
}
