import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/note.dart';
import '../theme/note_colors.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
  });

  final Note note;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final palette = NoteColors.of(note.bgColor);
    final df = DateFormat('MM-dd HH:mm');
    final preview = note.previewText();
    final firstLine = preview.split('\n').first;
    final restLines = preview.split('\n').skip(1).take(4).join('\n');

    final title = note.title.isNotEmpty
        ? note.title
        : (firstLine.isEmpty ? '(空便签)' : firstLine);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? palette.accent : Colors.black.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: palette.paperDark,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  if (note.isPinned)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.push_pin,
                          size: 16, color: palette.accent),
                    ),
                  if (note.alertAt != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.alarm,
                          size: 16, color: palette.accent),
                    ),
                  Expanded(
                    child: Text(
                      df.format(note.modifiedAt),
                      style: TextStyle(
                          color: palette.text.withOpacity(0.7), fontSize: 12),
                    ),
                  ),
                  if (selectionMode)
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: palette.accent,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                    ),
                  ),
                  if (restLines.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      restLines,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: palette.text.withOpacity(0.78),
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
