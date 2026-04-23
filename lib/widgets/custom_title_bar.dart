import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../providers/providers.dart';

/// 自定义无边框标题栏（拖动 / 置顶 / 透明度 / 最小化 / 关闭到托盘）。
class CustomTitleBar extends ConsumerWidget {
  const CustomTitleBar({super.key, this.title = '便签'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnTop = ref.watch(alwaysOnTopProvider);
    final opacity = ref.watch(windowOpacityProvider);

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => windowManager.startDragging(),
              // 不允许通过双击最大化（窗口已被锁定为 1040x650）。
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    const Icon(FluentIcons.quick_note, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 透明度滑杆
          SizedBox(
            width: 110,
            child: Slider(
              value: opacity,
              min: 0.4,
              max: 1.0,
              divisions: 12,
              label: '${(opacity * 100).round()}%',
              onChanged: (v) {
                ref.read(windowOpacityProvider.notifier).state = v;
                ref.read(windowServiceProvider).setOpacity(v);
              },
            ),
          ),
          // 置顶
          _TitleBarButton(
            icon: FluentIcons.pinned,
            tooltip: isOnTop ? '取消置顶' : '窗口置顶',
            highlight: isOnTop,
            onPressed: () async {
              final v = await ref.read(windowServiceProvider).toggleAlwaysOnTop();
              ref.read(alwaysOnTopProvider.notifier).state = v;
            },
          ),
          // 最小化
          _TitleBarButton(
            icon: FluentIcons.chrome_minimize,
            tooltip: '最小化',
            onPressed: () => windowManager.minimize(),
          ),
          // 关闭 -> 隐藏到托盘
          _TitleBarButton(
            icon: FluentIcons.chrome_close,
            tooltip: '关闭到托盘',
            danger: true,
            onPressed: () => ref.read(windowServiceProvider).hideToTray(),
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.highlight = false,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool highlight;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final btn = SizedBox(
      width: 40,
      height: 40,
      child: HoverButton(
        onPressed: onPressed,
        builder: (ctx, states) {
          Color? bg;
          if (states.isHovered) {
            bg = danger
                ? Colors.red.withValues(alpha: 0.85)
                : theme.resources.subtleFillColorSecondary;
          }
          final fg = danger && states.isHovered
              ? Colors.white
              : highlight
                  ? theme.accentColor
                  : null;
          return Container(
            color: bg,
            alignment: Alignment.center,
            child: Icon(icon, size: 14, color: fg),
          );
        },
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
