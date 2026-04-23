import 'package:fluent_ui/fluent_ui.dart';

import '../services/edge_hide_service.dart';

/// 当窗口处于"贴边隐藏"状态时，作为根布局覆盖一个透明感应层；
/// 鼠标悬停 -> 触发恢复。
///
/// 用法：将整个页面包在 [EdgeHideOverlay] 中。
class EdgeHideOverlay extends StatelessWidget {
  const EdgeHideOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HideSide>(
      stream: EdgeHideService.instance.hiddenSideStream,
      initialData: EdgeHideService.instance.side,
      builder: (context, snap) {
        final side = snap.data ?? HideSide.none;
        if (side == HideSide.none) return child;

        // 隐藏态时窗口已经只有 6px，整个窗口就是热区。
        return MouseRegion(
          opaque: true,
          onEnter: (_) => EdgeHideService.instance.restore(),
          child: Container(
            color: FluentTheme.of(context).accentColor.normal,
            alignment: Alignment.center,
            child: const Text(
              '⇆',
              style: TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        );
      },
    );
  }
}
