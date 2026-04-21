import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/folder.dart';
import '../../state/notes_store.dart';
import '../widgets/note_card.dart';
import 'folders_page.dart';
import 'note_edit_page.dart';
import 'search_page.dart';

class NotesListPage extends StatefulWidget {
  const NotesListPage({super.key});

  @override
  State<NotesListPage> createState() => _NotesListPageState();
}

class _NotesListPageState extends State<NotesListPage> {
  final Set<int> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  void _exitSelection() => setState(() => _selected.clear());

  void _toggleSelect(int id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Future<void> _bulkDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除便签'),
        content: Text('确定要删除选中的 ${_selected.length} 条便签吗？'),
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
    if (ok != true || !mounted) return;
    await context.read<NotesStore>().deleteNotes(_selected.toList());
    _exitSelection();
  }

  Future<void> _bulkMove() async {
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
                onTap: () => Navigator.pop(ctx, Folder.rootId),
              ),
              for (final f in store.folders)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  onTap: () => Navigator.pop(ctx, f.id),
                ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      await store.moveNotes(_selected.toList(), picked);
      _exitSelection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final notes = store.notes;

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              ),
              title: Text('已选 ${_selected.length} 项'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.drive_file_move_outline),
                  tooltip: '移动到文件夹',
                  onPressed: _bulkMove,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '删除',
                  onPressed: _bulkDelete,
                ),
              ],
            )
          : AppBar(
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: Text(store.currentFolderName()),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchPage()),
                    );
                  },
                ),
              ],
            ),
      drawer: const Drawer(child: FoldersPage()),
      body: notes.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: () => store.reloadAll(),
              child: ListView.builder(
                itemCount: notes.length,
                itemBuilder: (ctx, i) {
                  final n = notes[i];
                  return NoteCard(
                    note: n,
                    selected: _selected.contains(n.id),
                    selectionMode: _selectionMode,
                    onTap: () async {
                      if (_selectionMode) {
                        _toggleSelect(n.id);
                      } else {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => NoteEditPage(noteId: n.id),
                          ),
                        );
                      }
                    },
                    onLongPress: () => _toggleSelect(n.id),
                  );
                },
              ),
            ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => NoteEditPage(
                      folderId: store.currentFolderId == NotesStore.allFolderId
                          ? Folder.rootId
                          : store.currentFolderId,
                    ),
                  ),
                );
              },
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.sticky_note_2_outlined,
              size: 96, color: Colors.black.withOpacity(0.18)),
          const SizedBox(height: 16),
          const Text('还没有便签，点击右下角 + 新建一条吧'),
        ],
      ),
    );
  }
}
