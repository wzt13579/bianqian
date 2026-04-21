import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/folder.dart';
import '../../state/notes_store.dart';

class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NotesStore>();
    final counts = store.folderCounts;

    int countOf(int id) => counts[id] ?? 0;
    final totalCount =
        counts.values.fold<int>(0, (sum, v) => sum + v);
    final rootCount = countOf(Folder.rootId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文件夹'),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: '新建文件夹',
            onPressed: () => _createFolder(context),
          ),
        ],
      ),
      body: ListView(
        children: [
          _FolderTile(
            icon: Icons.style_outlined,
            title: '全部便签',
            count: totalCount,
            selected: store.currentFolderId == NotesStore.allFolderId,
            onTap: () async {
              await store.setCurrentFolder(NotesStore.allFolderId);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          _FolderTile(
            icon: Icons.note_outlined,
            title: '便签',
            count: rootCount,
            selected: store.currentFolderId == Folder.rootId,
            onTap: () async {
              await store.setCurrentFolder(Folder.rootId);
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const Divider(),
          for (final f in store.folders)
            _FolderTile(
              icon: Icons.folder_outlined,
              title: f.name,
              count: countOf(f.id),
              selected: store.currentFolderId == f.id,
              onTap: () async {
                await store.setCurrentFolder(f.id);
                if (context.mounted) Navigator.pop(context);
              },
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'rename') {
                    await _renameFolder(context, f);
                  } else if (v == 'delete') {
                    await _deleteFolder(context, f);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('重命名')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _createFolder(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '文件夹名称'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<NotesStore>().createFolder(name);
    }
  }

  Future<void> _renameFolder(BuildContext context, Folder f) async {
    final controller = TextEditingController(text: f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名文件夹'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('确定')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      await context.read<NotesStore>().renameFolder(f.id, name);
    }
  }

  Future<void> _deleteFolder(BuildContext context, Folder f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件夹'),
        content: Text('确定删除文件夹「${f.name}」？文件夹内的便签将移动到默认便签。'),
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
    if (ok == true && context.mounted) {
      await context.read<NotesStore>().deleteFolder(f.id);
    }
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title,
          style: TextStyle(
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
      subtitle: Text('$count 条'),
      selected: selected,
      onTap: onTap,
      trailing: trailing,
    );
  }
}
