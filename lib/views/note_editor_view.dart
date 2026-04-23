import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/note.dart';
import '../providers/providers.dart';
import '../services/import_export_service.dart';
import '../services/note_repository.dart';
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

  /// 缓存 repo 引用，避免 dispose 后还要通过 [ref] 取依赖。
  /// （ref 在 widget unmount 后访问会抛 "Cannot use ref after disposed"）
  NoteRepository? _repo;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController();
    _bodyCtrl = TextEditingController();
    _repo = ref.read(noteRepositoryProvider);
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
    final repo = _repo;
    if (repo == null) return;
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
              _TagBar(note: note),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(ref)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(WidgetRef ref) {
    final mode = ref.watch(editorModeProvider);
    final editor = Padding(
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
        onChanged: (_) {
          _save();
          // 触发预览刷新
          if (mounted) setState(() {});
        },
      ),
    );

    final preview = _MarkdownPreview(text: _bodyCtrl.text);

    switch (mode) {
      case EditorMode.edit:
        return editor;
      case EditorMode.preview:
        return preview;
      case EditorMode.split:
        return Row(
          children: [
            Expanded(child: editor),
            const SizedBox(
              width: 1,
              child: Divider(direction: Axis.vertical),
            ),
            Expanded(child: preview),
          ],
        );
    }
  }

  Widget _buildToolbar(Note note) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
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
          const SizedBox(width: 16),
          // 视图模式切换
          _ModeSwitcher(),
          const SizedBox(width: 4),
          Tooltip(
            message: '导出为 Markdown',
            child: IconButton(
              icon: const Icon(FluentIcons.share, size: 14),
              onPressed: () async {
                final p = await ImportExportService.instance
                    .exportNoteMarkdown(note);
                if (!mounted || p == null) return;
                showDialog<void>(
                  context: context,
                  builder: (_) => ContentDialog(
                    title: const Text('已导出'),
                    content: Text(p),
                    actions: [
                      FilledButton(
                          child: const Text('确定'),
                          onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                );
              },
            ),
          ),
          Tooltip(
            message: '保存 (Ctrl+S)',
            child: IconButton(
              icon: const Icon(FluentIcons.save, size: 14),
              onPressed: _save,
            ),
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

/// 视图模式切换按钮组（编辑 / 预览 / 分屏）。
class _ModeSwitcher extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(editorModeProvider);
    final theme = FluentTheme.of(context);

    Widget btn(EditorMode m, IconData icon, String tip) {
      final selected = mode == m;
      return Tooltip(
        message: tip,
        child: SizedBox(
          width: 28,
          height: 24,
          child: HoverButton(
            onPressed: () =>
                ref.read(editorModeProvider.notifier).state = m,
            builder: (_, states) {
              return Container(
                decoration: BoxDecoration(
                  color: selected
                      ? theme.accentColor.withValues(alpha: 0.18)
                      : (states.isHovered
                          ? theme.resources.subtleFillColorSecondary
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(
                  icon,
                  size: 13,
                  color: selected ? theme.accentColor : null,
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[40]),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(EditorMode.edit, FluentIcons.edit, '编辑'),
          btn(EditorMode.split, FluentIcons.column_options, '分屏'),
          btn(EditorMode.preview, FluentIcons.preview, '预览'),
        ],
      ),
    );
  }
}

/// Markdown 渲染区域。
class _MarkdownPreview extends StatelessWidget {
  const _MarkdownPreview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty) {
      return const Center(
        child: Text('（暂无内容）',
            style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
      );
    }
    return Markdown(
      data: text,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      selectable: true,
      shrinkWrap: false,
      styleSheet: MarkdownStyleSheet(
        p: const TextStyle(fontSize: 14, color: Colors.black, height: 1.55),
        h1: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: Colors.black),
        h2: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black),
        h3: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black),
        listBullet: const TextStyle(fontSize: 14, color: Colors.black),
        code: TextStyle(
          fontFamily: 'Consolas',
          fontSize: 13,
          backgroundColor: Colors.black.withValues(alpha: 0.06),
          color: Colors.black,
        ),
        codeblockDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquoteDecoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          border: Border(
            left: BorderSide(color: Colors.grey[80], width: 3),
          ),
        ),
        checkbox: const TextStyle(color: Colors.black),
      ),
      checkboxBuilder: (checked) => Padding(
        padding: const EdgeInsets.only(right: 4, top: 2),
        child: Icon(
          checked
              ? FluentIcons.checkbox_composite
              : FluentIcons.checkbox,
          size: 14,
          color: Colors.black,
        ),
      ),
    );
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

/// 编辑器中的"标签条"——展示当前便签的标签 + 添加新标签。
class _TagBar extends ConsumerWidget {
  const _TagBar({required this.note});
  final Note note;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(noteRepositoryProvider);
    final allTags = ref.watch(allTagsProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...note.tags.map((t) => _TagChip(
                label: t,
                onRemove: () async {
                  final next = List<String>.from(note.tags)..remove(t);
                  await repo.setTags(note.id, next);
                },
              )),
          // "+ 添加标签"按钮 + 弹出已有标签
          ComboBox<String>(
            placeholder: const Text('+ 标签', style: TextStyle(fontSize: 11)),
            isExpanded: false,
            items: [
              ...allTags
                  .where((t) => !note.tags.contains(t))
                  .map((t) => ComboBoxItem<String>(
                        value: t,
                        child: Text('#$t'),
                      )),
              const ComboBoxItem<String>(
                value: '__new__',
                child: Text('＋ 新建标签…'),
              ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              if (value == '__new__') {
                final newTag = await _promptNewTag(context);
                if (newTag != null && newTag.isNotEmpty) {
                  final next = List<String>.from(note.tags)..add(newTag);
                  await repo.setTags(note.id, next);
                }
              } else {
                final next = List<String>.from(note.tags)..add(value);
                await repo.setTags(note.id, next);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _promptNewTag(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('新建标签'),
        content: TextBox(controller: ctrl, placeholder: '标签名称'),
        actions: [
          Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('添加'),
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label, required this.onRemove});
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 3, 4, 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[60]),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('#$label',
              style:
                  const TextStyle(fontSize: 11, color: Colors.black)),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: const Icon(FluentIcons.chrome_close,
                size: 9, color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }
}
