import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../models/note.dart';

/// 便签列表中的卡片项。
class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.selected,
    required this.onTap,
    required this.onTogglePin,
    required this.onDelete,
  });

  final Note note;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final preview = _firstLine(note.content);

    return HoverButton(
      onPressed: onTap,
      builder: (context, states) {
        final isHover = states.isHovered;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Color(note.color).withValues(alpha: isHover ? 1 : 0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? theme.accentColor : Colors.transparent,
              width: 1.5,
            ),
            boxShadow: [
              if (isHover)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      note.title.isEmpty ? '(无标题)' : note.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  if (note.isPinned)
                    const Icon(FluentIcons.pinned_solid,
                        size: 12, color: Colors.black),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF555555),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    DateFormat('MM-dd HH:mm').format(note.updateTime),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF888888),
                    ),
                  ),
                  const Spacer(),
                  if (isHover) ...[
                    _MiniIcon(
                      icon: note.isPinned
                          ? FluentIcons.unpin
                          : FluentIcons.pin,
                      onPressed: onTogglePin,
                    ),
                    const SizedBox(width: 6),
                    _MiniIcon(
                      icon: FluentIcons.delete,
                      onPressed: onDelete,
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _firstLine(String text) {
    final s = text.replaceAll(RegExp(r'[#*>`\-]+\s?'), '').trim();
    if (s.isEmpty) return '(空白便签)';
    final idx = s.indexOf('\n');
    return idx == -1 ? s : s.substring(0, idx);
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, size: 12, color: Colors.black),
      ),
    );
  }
}
