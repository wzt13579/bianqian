import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../providers/providers.dart';

/// 回收站中单条便签的预览（只读）+ 操作（恢复 / 永久删除）。
class TrashDetailView extends ConsumerWidget {
  const TrashDetailView({super.key, required this.noteId});

  final String noteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final note = ref.watch(noteByIdProvider(noteId));
    if (note == null) return const Center(child: Text('便签不存在'));

    final repo = ref.read(noteRepositoryProvider);

    return Container(
      color: Color(note.color).withValues(alpha: 0.6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.red.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(FluentIcons.delete, size: 14, color: Colors.red),
                const SizedBox(width: 6),
                Text('该便签在回收站中（只读）',
                    style: TextStyle(color: Colors.red, fontSize: 12)),
                const Spacer(),
                Button(
                  child: const Text('恢复'),
                  onPressed: () async {
                    await repo.restore(noteId);
                  },
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStatePropertyAll(Colors.red),
                  ),
                  child: const Text('永久删除'),
                  onPressed: () async {
                    await showDialog<void>(
                      context: context,
                      builder: (_) => ContentDialog(
                        title: const Text('永久删除此便签？'),
                        content: const Text('该操作不可恢复。'),
                        actions: [
                          Button(
                              child: const Text('取消'),
                              onPressed: () => Navigator.pop(context)),
                          FilledButton(
                            style: ButtonStyle(
                              backgroundColor:
                                  WidgetStatePropertyAll(Colors.red),
                            ),
                            child: const Text('删除'),
                            onPressed: () async {
                              await repo.hardDelete(noteId);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              note.title.isEmpty ? '(无标题)' : note.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '更新于 ${DateFormat('yyyy-MM-dd HH:mm').format(note.updateTime)}',
              style:
                  const TextStyle(fontSize: 11, color: Color(0xFF666666)),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: SelectableText(
                note.content,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
