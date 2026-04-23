import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

/// 贴边隐藏（类似 QQ / 好用便签）。
///
/// 行为：
/// - 当窗口顶/左/右边缘距离屏幕边缘 ≤ [snapThreshold] 像素时，
///   将窗口缩为 [hiddenStripSize] 大小，留一个细条贴在屏幕边。
/// - UI 层通过 [hiddenSideStream] 监听当前隐藏方向；当鼠标移入窗口区域，
///   调用 [restore] 恢复原尺寸。
enum HideSide { none, top, left, right }

class EdgeHideService {
  EdgeHideService._();
  static final EdgeHideService instance = EdgeHideService._();

  /// 贴边触发阈值（像素）。
  static const double snapThreshold = 6.0;

  /// 隐藏后的"细条"宽/高（像素）。
  static const double hiddenStripSize = 6.0;

  bool _enabled = false;
  bool _busy = false;

  Rect? _restoreFrame;
  HideSide _side = HideSide.none;

  HideSide get side => _side;

  final StreamController<HideSide> _sideCtrl = StreamController.broadcast();
  Stream<HideSide> get hiddenSideStream => _sideCtrl.stream;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  void enable() {
    _enabled = _isDesktop;
  }

  void disable() {
    _enabled = false;
  }

  /// 由 WindowListener.onWindowMoved / onWindowResize 调用。
  Future<void> onWindowMoved() async {
    if (!_enabled || _busy) return;
    _busy = true;
    try {
      // 已处于隐藏态时不再重复触发吸附。
      if (_side != HideSide.none) return;

      final display = await screenRetriever.getPrimaryDisplay();
      final pos = await windowManager.getPosition();
      final size = await windowManager.getSize();
      final screenSize = display.size;

      HideSide newSide = HideSide.none;
      if (pos.dy <= snapThreshold) {
        newSide = HideSide.top;
      } else if (pos.dx <= snapThreshold) {
        newSide = HideSide.left;
      } else if (pos.dx + size.width >= screenSize.width - snapThreshold) {
        newSide = HideSide.right;
      }

      if (newSide != HideSide.none) {
        _restoreFrame = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
        await _applyHide(newSide, screenSize);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _applyHide(HideSide newSide, Size screenSize) async {
    _side = newSide;
    _sideCtrl.add(newSide);

    switch (newSide) {
      case HideSide.top:
        await windowManager.setBounds(
          Rect.fromLTWH(0, 0, screenSize.width, hiddenStripSize),
        );
        break;
      case HideSide.left:
        await windowManager.setBounds(
          Rect.fromLTWH(0, 0, hiddenStripSize, screenSize.height),
        );
        break;
      case HideSide.right:
        await windowManager.setBounds(
          Rect.fromLTWH(
            screenSize.width - hiddenStripSize,
            0,
            hiddenStripSize,
            screenSize.height,
          ),
        );
        break;
      case HideSide.none:
        break;
    }
    await windowManager.setAlwaysOnTop(true);
  }

  /// 鼠标进入"细条"时调用恢复。
  Future<void> restore() async {
    if (!_enabled || _side == HideSide.none) return;
    _busy = true;
    try {
      final f = _restoreFrame;
      if (f != null) {
        await windowManager.setBounds(f);
      }
      _side = HideSide.none;
      _restoreFrame = null;
      _sideCtrl.add(HideSide.none);
    } finally {
      _busy = false;
    }
  }

  /// 用户在 UI 中手动取消"贴边停留"——例如点击按钮拖回中心。
  Future<void> moveAwayFromEdge(Offset target) async {
    await windowManager.setPosition(target);
    await restore();
  }

  void dispose() {
    _sideCtrl.close();
  }
}
