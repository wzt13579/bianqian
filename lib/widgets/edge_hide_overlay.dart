import 'package:fluent_ui/fluent_ui.dart';

import '../services/edge_hide_service.dart';

/// 整个根布局外层包一层 [MouseRegion]，把"鼠标进入 / 离开窗口"
/// 事件转发给 [EdgeHideService]：
/// - 鼠标进入 → 立即滑入；
/// - 鼠标离开 → 由 service 调度 700ms 后滑出。
///
/// 这种实现下我们**不改变窗口尺寸**（保持 1040×650），完全靠
/// 移动窗口位置达成 QQ 风格的"窗口外推 + 留 5px peek"效果。
class EdgeHideOverlay extends StatelessWidget {
  const EdgeHideOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DockState>(
      stream: EdgeHideService.instance.stateStream,
      initialData: EdgeHideService.instance.state,
      builder: (context, snap) {
        final state = snap.data ?? DockState.free;

        // hidden 状态下窗口大部分被推出屏幕，只剩 5px peek 在屏幕内。
        // 此时把根布局换成一个高亮"提示条"，让 5px 内的 onEnter 一定能命中。
        if (state == DockState.hidden) {
          return MouseRegion(
            opaque: true,
            onEnter: (_) => EdgeHideService.instance.onMouseEnter(),
            child: _PeekStrip(side: EdgeHideService.instance.side),
          );
        }

        // free / docked 都正常渲染 child；docked 时还要监听 onExit
        // 触发延迟滑出。
        return MouseRegion(
          onEnter: (_) => EdgeHideService.instance.onMouseEnter(),
          onExit: (_) => EdgeHideService.instance.onMouseExit(),
          child: child,
        );
      },
    );
  }
}

/// 隐藏态下覆盖整个窗口的"高亮 peek 条"。
/// 因为窗口已被推出屏幕，整个窗口剩下的可视区域 = peek 条。
class _PeekStrip extends StatelessWidget {
  const _PeekStrip({required this.side});
  final HideSide side;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: switch (side) {
            HideSide.top => Alignment.topCenter,
            HideSide.left => Alignment.centerLeft,
            HideSide.right => Alignment.centerRight,
            HideSide.none => Alignment.center,
          },
          end: switch (side) {
            HideSide.top => Alignment.bottomCenter,
            HideSide.left => Alignment.centerRight,
            HideSide.right => Alignment.centerLeft,
            HideSide.none => Alignment.center,
          },
          colors: [
            theme.accentColor.darker,
            theme.accentColor.normal,
          ],
        ),
      ),
    );
  }
}
