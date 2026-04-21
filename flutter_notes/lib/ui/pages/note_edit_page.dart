import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/folder.dart';
import '../../models/note.dart';
import '../../state/notes_store.dart';
import '../theme/note_colors.dart';

class NoteEditPage extends StatefulWidget {
  const NoteEditPage({super.key, this.noteId, this.folderId});

  final int? noteId;
  final int? folderId;

  @override
  State<NoteEditPage> createState() => _NoteEditPageState();
}

class _NoteEditPageState extends State<NoteEditPage> {
  late Note _note;
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  List<_EditableChecklistItem> _checklist = [];
  bool _loaded = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = context.read<NotesStore>();
    if (widget.noteId != null) {
      final found = store.notes.firstWhere(
        (n) => n.id == widget.noteId,
        orElse: () => Note(
          createdAt: DateTime.now(),
          modifiedAt: DateTime.now(),
        ),
      );
      _note = found;
    } else {
      _note = Note(
        folderId: widget.folderId ??
            (store.currentFolderId == NotesStore.allFolderId
                ? Folder.rootId
                : store.currentFolderId),
        createdAt: DateTime.now(),
        modifiedAt: DateTime.now(),
      );
    }
    _titleCtrl.text = _note.title;
    _contentCtrl.text = _note.content;
    _checklist = _note.checklistItems
        .map((e) => _EditableChecklistItem(
              text: e.text,
              done: e.done,
              controller: TextEditingController(text: e.text),
            ))
        .toList();
    if (_note.type == NoteType.checklist && _checklist.isEmpty) {
      _addChecklistItem();
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    for (final i in _checklist) {
      i.controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _addChecklistItem() {
    setState(() {
      _checklist.add(_EditableChecklistItem(
        text: '',
        done: false,
        controller: TextEditingController(),
      ));
      _dirty = true;
    });
  }

  Future<bool> _saveIfNeeded() async {
    final hasContent = _note.type == NoteType.text
        ? _contentCtrl.text.trim().isNotEmpty || _titleCtrl.text.trim().isNotEmpty
        : _checklist.any((e) => e.controller.text.trim().isNotEmpty) ||
            _titleCtrl.text.trim().isNotEmpty;

    if (!hasContent && _note.id == 0) {
      return true;
    }
    if (!_dirty && _note.id != 0) {
      return true;
    }

    final store = context.read<NotesStore>();
    final content = _note.type == NoteType.text
        ? _contentCtrl.text
        : Note.encodeChecklist(_checklist
            .where((e) => e.controller.text.trim().isNotEmpty)
            .map((e) => ChecklistItem(text: e.controller.text, done: e.done))
            .toList());

    final saved = _note.copyWith(
      title: _titleCtrl.text.trim(),
      content: content,
      modifiedAt: DateTime.now(),
    );
    await store.saveNote(saved);
    return true;
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _note.alertAt ?? now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay.fromDateTime(_note.alertAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _note = _note.copyWith(alertAt: dt);
      _dirty = true;
    });
  }

  void _clearReminder() {
    setState(() {
      _note = _note.copyWith(clearAlert: true);
      _dirty = true;
    });
  }

  Future<void> _pickColor() async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < NoteColors.palettes.length; i++)
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx, i),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: NoteColors.palettes[i].paper,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: i == _note.bgColor
                              ? NoteColors.palettes[i].accent
                              : Colors.black12,
                          width: i == _note.bgColor ? 3 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(NoteColors.palettes[i].name,
                          style: TextStyle(
                              color: NoteColors.palettes[i].text,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _note = _note.copyWith(bgColor: picked);
        _dirty = true;
      });
    }
  }

  Future<void> _pickFolder() async {
    final store = context.read<NotesStore>();
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.note_outlined),
                title: const Text('便签'),
                selected: _note.folderId == Folder.rootId,
                onTap: () => Navigator.pop(ctx, Folder.rootId),
              ),
              for (final f in store.folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  selected: _note.folderId == f.id,
                  onTap: () => Navigator.pop(ctx, f.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _note = _note.copyWith(folderId: picked);
        _dirty = true;
      });
    }
  }

  void _toggleType() {
    setState(() {
      if (_note.type == NoteType.text) {
        final lines = _contentCtrl.text
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        _checklist = lines.isEmpty
            ? [
                _EditableChecklistItem(
                  text: '',
                  done: false,
                  controller: TextEditingController(),
                )
              ]
            : lines
                .map((l) => _EditableChecklistItem(
                      text: l,
                      done: false,
                      controller: TextEditingController(text: l),
                    ))
                .toList();
        _note = _note.copyWith(type: NoteType.checklist);
      } else {
        _contentCtrl.text = _checklist
            .map((e) => '${e.done ? '☑' : '☐'} ${e.controller.text}')
            .join('\n');
        _note = _note.copyWith(type: NoteType.text);
      }
      _dirty = true;
    });
  }

  Future<void> _deleteNote() async {
    if (_note.id == 0) {
      Navigator.pop(context);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除便签'),
        content: const Text('确定要删除这条便签吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<NotesStore>().deleteNotes([_note.id]);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final palette = NoteColors.of(_note.bgColor);
    final df = DateFormat('yyyy-MM-dd HH:mm');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        await _saveIfNeeded();
        if (mounted) nav.pop();
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          scaffoldBackgroundColor: palette.paper,
          appBarTheme: AppBarTheme(
            backgroundColor: palette.paperDark,
            foregroundColor: palette.text,
            elevation: 0,
            iconTheme: IconThemeData(color: palette.text),
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: palette.accent,
            selectionColor: palette.accent.withOpacity(0.3),
            selectionHandleColor: palette.accent,
          ),
        ),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () async {
                final nav = Navigator.of(context);
                await _saveIfNeeded();
                if (mounted) nav.pop();
              },
            ),
            title: Text(df.format(_note.modifiedAt),
                style: const TextStyle(fontSize: 14)),
            actions: [
              IconButton(
                icon: Icon(_note.type == NoteType.text
                    ? Icons.checklist
                    : Icons.notes),
                tooltip: _note.type == NoteType.text ? '清单模式' : '文本模式',
                onPressed: _toggleType,
              ),
              IconButton(
                icon: const Icon(Icons.color_lens_outlined),
                tooltip: '便签颜色',
                onPressed: _pickColor,
              ),
              IconButton(
                icon: const Icon(Icons.alarm),
                tooltip: '提醒',
                onPressed: _pickReminder,
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'folder') _pickFolder();
                  if (v == 'pin') {
                    setState(() {
                      _note = _note.copyWith(isPinned: !_note.isPinned);
                      _dirty = true;
                    });
                  }
                  if (v == 'clear_alert') _clearReminder();
                  if (v == 'delete') _deleteNote();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'folder', child: Text('移动到文件夹')),
                  PopupMenuItem(
                      value: 'pin',
                      child: Text(_note.isPinned ? '取消置顶' : '置顶')),
                  if (_note.alertAt != null)
                    const PopupMenuItem(
                        value: 'clear_alert', child: Text('取消提醒')),
                  const PopupMenuItem(value: 'delete', child: Text('删除便签')),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (_note.alertAt != null)
                Container(
                  width: double.infinity,
                  color: palette.accent.withOpacity(0.2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.alarm,
                          size: 16, color: palette.accent),
                      const SizedBox(width: 6),
                      Text(
                        '提醒：${df.format(_note.alertAt!)}',
                        style: TextStyle(
                            color: palette.text, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: TextField(
                  controller: _titleCtrl,
                  onChanged: (_) => _markDirty(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                  decoration: const InputDecoration(
                    hintText: '标题',
                    border: InputBorder.none,
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: _note.type == NoteType.text
                    ? _buildTextEditor(palette)
                    : _buildChecklistEditor(palette),
              ),
            ],
          ),
          floatingActionButton: _note.type == NoteType.checklist
              ? FloatingActionButton(
                  backgroundColor: palette.accent,
                  onPressed: _addChecklistItem,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildTextEditor(NoteColorPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _contentCtrl,
        onChanged: (_) => _markDirty(),
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: 16,
          color: palette.text,
          height: 1.5,
        ),
        decoration: const InputDecoration(
          hintText: '在这里写下点什么...',
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildChecklistEditor(NoteColorPalette palette) {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _checklist.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = _checklist.removeAt(oldIndex);
          _checklist.insert(newIndex, item);
          _dirty = true;
        });
      },
      itemBuilder: (ctx, i) {
        final item = _checklist[i];
        return Container(
          key: ValueKey(item),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              Checkbox(
                value: item.done,
                activeColor: palette.accent,
                onChanged: (v) {
                  setState(() {
                    item.done = v ?? false;
                    _dirty = true;
                  });
                },
              ),
              Expanded(
                child: TextField(
                  controller: item.controller,
                  onChanged: (_) => _markDirty(),
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: '清单项',
                  ),
                ),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(Icons.drag_handle, color: Colors.black38),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.black38),
                onPressed: () {
                  setState(() {
                    _checklist.removeAt(i);
                    _dirty = true;
                    if (_checklist.isEmpty) _addChecklistItem();
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EditableChecklistItem {
  String text;
  bool done;
  final TextEditingController controller;
  _EditableChecklistItem({
    required this.text,
    required this.done,
    required this.controller,
  });
}
