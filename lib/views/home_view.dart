import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/note_card.dart';
import 'note_editor_view.dart';

/// 主面板：左侧便签列表 + 顶部搜索 + 右侧编辑器。
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(filteredNotesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);

    final effectiveSelectedId = selectedId ??
        (notes.isNotEmpty ? notes.first.id : null);

    return Container(
      color: FluentTheme.of(context).micaBackgroundColor,
      child: Column(
        children: [
          const CustomTitleBar(title: '便签 Bianqian'),
          const Divider(style: DividerThemeData(thickness: 0.5)),
          Expanded(
            child: Row(
              children: [
                SizedBox(width: 280, child: _NoteListPanel()),
                const Divider(direction: Axis.vertical),
                Expanded(
                  child: effectiveSelectedId == null
                      ? const _EmptyEditor()
                      : NoteEditorView(
                          key: ValueKey(effectiveSelectedId),
                          noteId: effectiveSelectedId,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteListPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes = ref.watch(filteredNotesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);
    final keyword = ref.watch(searchKeywordProvider);
    final repo = ref.read(noteRepositoryProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  placeholder: '搜索便签…',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 14),
                  ),
                  onChanged: (v) =>
                      ref.read(searchKeywordProvider.notifier).state = v,
                  controller: TextEditingController(text: keyword)
                    ..selection = TextSelection.collapsed(offset: keyword.length),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '新建便签 (Ctrl+N)',
                child: IconButton(
                  icon: const Icon(FluentIcons.add, size: 16),
                  onPressed: () async {
                    final note = await repo.create();
                    ref.read(selectedNoteIdProvider.notifier).state = note.id;
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? const Center(
                  child: Text(
                    '暂无便签\n点击右上角 + 新建',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF888888)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: notes.length,
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    return NoteCard(
                      note: note,
                      selected: note.id == selectedId,
                      onTap: () => ref
                          .read(selectedNoteIdProvider.notifier)
                          .state = note.id,
                      onTogglePin: () => repo.togglePin(note.id),
                      onDelete: () async {
                        await repo.softDelete(note.id);
                        if (selectedId == note.id) {
                          ref.read(selectedNoteIdProvider.notifier).state = null;
                        }
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(FluentIcons.edit_note, size: 64, color: Color(0xFFBBBBBB)),
          SizedBox(height: 12),
          Text(
            '选择一个便签开始编辑',
            style: TextStyle(color: Color(0xFF888888), fontSize: 14),
          ),
        ],
      ),
    );
  }
}
