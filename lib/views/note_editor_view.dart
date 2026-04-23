import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';

/// 便签编辑器（标题 + Markdown 内容 + 工具栏）。
class NoteEditorView extends ConsumerStatefulWidget {
  const NoteEditorView({super.key, required this.noteId});

  final String noteId;

  @override
  ConsumerState<NoteEditorView> createState() => _NoteEditorViewState();
}

class _NoteEditorViewState extends ConsumerState<NoteEditorView> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  String _loadedNoteId = '';

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _bodyCtrl = TextEditingController();
    _syncFromNote();
  }

  void _syncFromNote() {
    final note = ref.read(noteByIdProvider(widget.noteId));
    if (note == null) return;
    _loadedNoteId = note.id;
    _titleCtrl.text = note.title;
    _bodyCtrl.text = note.content;
  }

  Future<void> _save() async {
    final repo = ref.read(noteRepositoryProvider);
    final note = repo.getById(widget.noteId);
    if (note == null) return;
    note.title = _titleCtrl.text;
    note.content = _bodyCtrl.text;
    await repo.update(note);
  }

  /// 在选区两侧插入标记（Markdown 加粗 / 斜体 等）。
  void _wrap(String prefix, [String? suffix]) {
    final s = suffix ?? prefix;
    final sel = _bodyCtrl.selection;
    final text = _bodyCtrl.text;
    if (!sel.isValid) return;
    final selected = sel.textInside(text);
    final newText = sel.textBefore(text) + prefix + selected + s + sel.textAfter(text);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: sel.start + prefix.length + selected.length + s.length,
      ),
    );
  }

  void _insertLinePrefix(String prefix) {
    final sel = _bodyCtrl.selection;
    if (!sel.isValid) return;
    final text = _bodyCtrl.text;
    int lineStart = text.lastIndexOf('\n', sel.start - 1) + 1;
    final newText = text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _bodyCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: sel.start + prefix.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadedNoteId != widget.noteId) {
      _syncFromNote();
    }
    final note = ref.watch(noteByIdProvider(widget.noteId));
    if (note == null) {
      return const Center(child: Text('便签不存在或已被删除'));
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: Color(note.color),
          child: Column(
            children: [
              _buildToolbar(note),
              const Divider(style: DividerThemeData(thickness: 0.5)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextBox(
                  controller: _titleCtrl,
                  placeholder: '标题',
                  unfocusedColor: Colors.transparent,
                  decoration: const WidgetStatePropertyAll(BoxDecoration()),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                  onChanged: (_) => _save(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: TextBox(
                    controller: _bodyCtrl,
                    maxLines: null,
                    expands: true,
                    placeholder: '在这里输入内容…  支持 Markdown：**加粗**  - 列表  - [ ] 待办',
                    unfocusedColor: Colors.transparent,
                    decoration: const WidgetStatePropertyAll(BoxDecoration()),
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xDE000000),
                      height: 1.5,
                    ),
                    onChanged: (_) => _save(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(Note note) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          _ToolBtn(icon: FluentIcons.bold, tooltip: '加粗 (**文字**)', onPressed: () => _wrap('**')),
          _ToolBtn(icon: FluentIcons.italic, tooltip: '斜体 (*文字*)', onPressed: () => _wrap('*')),
          _ToolBtn(icon: FluentIcons.bulleted_list, tooltip: '无序列表', onPressed: () => _insertLinePrefix('- ')),
          _ToolBtn(icon: FluentIcons.number_symbol, tooltip: '有序列表', onPressed: () => _insertLinePrefix('1. ')),
          _ToolBtn(icon: FluentIcons.checkbox, tooltip: '待办勾选框', onPressed: () => _insertLinePrefix('- [ ] ')),
          const SizedBox(width: 8),
          const SizedBox(
            height: 20,
            child: Divider(direction: Axis.vertical),
          ),
          const SizedBox(width: 8),
          // 颜色选择
          ...AppTheme.noteColors.map(
            (c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GestureDetector(
                onTap: () async {
                  final repo = ref.read(noteRepositoryProvider);
                  note.color = c.toARGB32();
                  await repo.update(note);
                },
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: note.color == c.toARGB32()
                          ? Colors.black
                          : Colors.grey[60],
                      width: note.color == c.toARGB32() ? 2 : 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(FluentIcons.save, size: 14),
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _save();
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 14),
        onPressed: onPressed,
      ),
    );
  }
}
