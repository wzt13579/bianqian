import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'native_window.dart';

/// 子窗口（独立便签窗口）专用的贴边隐藏。
///
/// 主窗口的 [EdgeHideService] 直接依赖 `window_manager`，但子窗口里
/// `window_manager` 不可用 —— 所以这里完全走 win32 ffi（[NativeWindow]）：
/// - 用 `GetWindowRect` 周期性轮询窗口位置，判断是否贴边；
/// - 用 `SetWindowPos` 移动窗口完成滑入 / 滑出动画。
///
/// 与主窗口的实现保持一致的语义：
/// - 拖到屏幕边缘自动 docked；
/// - 鼠标离开窗口 700ms 后滑出，仅留 5px peek；
/// - 鼠标进入窗口（含 peek）滑回。
enum _Side { none, top, left, right }

enum SubDockState { free, docked, hidden }

class SubWindowEdgeHide {
  SubWindowEdgeHide({required this.hwnd});

  final int hwnd;

  // --- 配置 ---
  static const double snapThreshold = 8.0;
  static const int peekSize = 5;
  static const Duration autoHideDelay = Duration(milliseconds: 700);
  static const Duration animationDuration = Duration(milliseconds: 180);
  static const int _animationFrames = 14;
  static const Duration _pollInterval = Duration(milliseconds: 400);

  // --- 状态 ---
  bool _enabled = false;
  bool _animating = false;
  _Side _side = _Side.none;
  SubDockState _state = SubDockState.free;

  /// docked 时窗口完整可见的位置。
  ({int x, int y, int w, int h})? _dockedRect;

  /// hidden 时窗口推出屏幕的位置。
  ({int x, int y, int w, int h})? _hiddenRect;

  Timer? _pollTimer;
  Timer? _hideTimer;

  /// hidden 期间是否被本服务"临时置顶"了；slideIn 时需要回退。
  bool _tempOnTop = false;

  final StreamController<SubDockState> _stateCtrl =
      StreamController<SubDockState>.broadcast();
  Stream<SubDockState> get stateStream => _stateCtrl.stream;
  SubDockState get state => _state;

  void enable() {
    if (_enabled || hwnd == 0) return;
    _enabled = true;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollPosition());
  }

  void disable() {
    _enabled = false;
    _pollTimer?.cancel();
    _hideTimer?.cancel();
    _pollTimer = null;
    _hideTimer = null;
  }

  void dispose() {
    disable();
    _stateCtrl.close();
  }

  // ============== 鼠标事件（由 UI 调用） ==============

  void onMouseEnter() {
    if (!_enabled || _side == _Side.none) return;
    _hideTimer?.cancel();
    if (_state == SubDockState.hidden) {
      _slideIn();
    }
  }

  void onMouseExit() {
    if (!_enabled || _side == _Side.none) return;
    _hideTimer?.cancel();
    if (_state == SubDockState.docked) {
      _hideTimer = Timer(autoHideDelay, () {
        if (_state == SubDockState.docked) _slideOut();
      });
    }
  }

  // ============== 内部 ==============

  void _pollPosition() {
    if (!_enabled || _animating) return;
    if (_state == SubDockState.hidden) return;
    final (l, t, w, h) = NativeWindow.getRect(hwnd);
    if (w == 0 || h == 0) return;
    final (sw, sh) = NativeWindow.getPrimaryScreenSize();

    final near = _detectEdge(l, t, w, sw);
    if (near == _Side.none) {
      if (_state == SubDockState.docked) _setState(SubDockState.free);
      _side = _Side.none;
      _dockedRect = null;
      _hiddenRect = null;
      return;
    }

    final docked = _alignToEdge(near, l, t, w, h, sw);
    _side = near;
    _dockedRect = docked;
    _hiddenRect = _hiddenRectFor(near, docked, sw);
    if (_state != SubDockState.docked) {
      _setState(SubDockState.docked);
    }
    if ((l - docked.x).abs() > 1 || (t - docked.y).abs() > 1) {
      NativeWindow.moveTo(hwnd, docked.x, docked.y);
    }
  }

  _Side _detectEdge(int l, int t, int w, int sw) {
    if (t <= snapThreshold) return _Side.top;
    if (l <= snapThreshold) return _Side.left;
    if (l + w >= sw - snapThreshold) return _Side.right;
    return _Side.none;
  }

  ({int x, int y, int w, int h}) _alignToEdge(
      _Side side, int l, int t, int w, int h, int sw) {
    switch (side) {
      case _Side.top:
        return (x: l, y: 0, w: w, h: h);
      case _Side.left:
        return (x: 0, y: t, w: w, h: h);
      case _Side.right:
        return (x: sw - w, y: t, w: w, h: h);
      case _Side.none:
        return (x: l, y: t, w: w, h: h);
    }
  }

  ({int x, int y, int w, int h}) _hiddenRectFor(
      _Side side, ({int x, int y, int w, int h}) d, int sw) {
    switch (side) {
      case _Side.top:
        return (x: d.x, y: -(d.h - peekSize), w: d.w, h: d.h);
      case _Side.left:
        return (x: -(d.w - peekSize), y: d.y, w: d.w, h: d.h);
      case _Side.right:
        return (x: sw - peekSize, y: d.y, w: d.w, h: d.h);
      case _Side.none:
        return d;
    }
  }

  Future<void> _slideOut() async {
    final from = _dockedRect, to = _hiddenRect;
    if (from == null || to == null) return;
    if (!NativeWindow.isAlwaysOnTop(hwnd)) {
      NativeWindow.setAlwaysOnTop(hwnd, true);
      _tempOnTop = true;
    }
    await _animateMove(from.x, from.y, to.x, to.y);
    _setState(SubDockState.hidden);
  }

  Future<void> _slideIn() async {
    final from = _hiddenRect, to = _dockedRect;
    if (from == null || to == null) return;
    await _animateMove(from.x, from.y, to.x, to.y);
    if (_tempOnTop) {
      NativeWindow.setAlwaysOnTop(hwnd, false);
      _tempOnTop = false;
    }
    _setState(SubDockState.docked);
  }

  Future<void> _animateMove(int fx, int fy, int tx, int ty) async {
    _animating = true;
    try {
      final stepMs =
          (animationDuration.inMilliseconds / _animationFrames).round();
      for (int i = 1; i <= _animationFrames; i++) {
        final t = _easeOut(i / _animationFrames);
        final x = (fx + (tx - fx) * t).round();
        final y = (fy + (ty - fy) * t).round();
        NativeWindow.moveTo(hwnd, x, y);
        await Future<void>.delayed(Duration(milliseconds: stepMs));
      }
      NativeWindow.moveTo(hwnd, tx, ty);
    } finally {
      _animating = false;
    }
  }

  double _easeOut(double t) {
    final inv = 1 - t;
    return 1 - math.pow(inv, 3).toDouble();
  }

  void _setState(SubDockState s) {
    if (_state == s) return;
    _state = s;
    _stateCtrl.add(s);
    if (kDebugMode) debugPrint('[SubEdgeHide] state -> $s, side=$_side');
  }
}
