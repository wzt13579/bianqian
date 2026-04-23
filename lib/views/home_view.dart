import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart'
    show Material, MaterialType, ReorderableListView;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/import_export_service.dart';
import '../widgets/custom_title_bar.dart';
import '../widgets/edge_hide_overlay.dart';
import '../widgets/note_card.dart';
import 'note_editor_view.dart';
import 'trash_view.dart';

/// 主面板：标题栏 + 左侧导航 + 中间列表 + 右侧编辑器。
class HomeView extends ConsumerWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EdgeHideOverlay(
      child: Container(
        color: FluentTheme.of(context).micaBackgroundColor,
        child: Column(
          children: [
            const CustomTitleBar(title: '便签 Bianqian'),
            const Divider(style: DividerThemeData(thickness: 0.5)),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 200, child: _SideNav()),
                  const Divider(direction: Axis.vertical),
                  const SizedBox(width: 280, child: _NoteListPanel()),
                  const Divider(direction: Axis.vertical),
                  Expanded(child: _RightPane()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左侧导航：全部 / 标签 / 回收站。
class _SideNav extends ConsumerWidget {
  const _SideNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navSelectionProvider);
    final tags = ref.watch(allTagsProvider);
    final trashCount = ref.watch(trashCountProvider);
    final theme = FluentTheme.of(context);

    Color? bgFor(bool selected) =>
        selected ? theme.accentColor.withValues(alpha: 0.15) : null;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _NavItem(
          icon: FluentIcons.all_apps,
          label: '全部便签',
          selected: nav.mode == NavMode.allNotes,
          background: bgFor(nav.mode == NavMode.allNotes),
          onTap: () => ref.read(navSelectionProvider.notifier).state =
              NavSelection.all,
        ),
        const SizedBox(height: 4),
        _SectionHeader(
          title: '标签',
          trailing: IconButton(
            icon: const Icon(FluentIcons.add, size: 12),
            onPressed: () => _showAddTagDialog(context, ref),
          ),
        ),
        if (tags.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('（暂无标签）',
                style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
          ),
        ...tags.map((t) {
          final selected = nav.mode == NavMode.tag && nav.tag == t;
          return _NavItem(
            icon: FluentIcons.tag,
            label: '#$t',
            selected: selected,
            background: bgFor(selected),
            onTap: () => ref.read(navSelectionProvider.notifier).state =
                NavSelection.byTag(t),
            onLongPress: () => _showRenameTagSheet(context, ref, t),
          );
        }),
        const Divider(),
        _NavItem(
          icon: FluentIcons.delete,
          label: '回收站',
          selected: nav.mode == NavMode.trash,
          background: bgFor(nav.mode == NavMode.trash),
          badge: trashCount,
          onTap: () => ref.read(navSelectionProvider.notifier).state =
              NavSelection.trash,
        ),
        const Divider(),
        _SectionHeader(title: '数据'),
        _NavItem(
          icon: FluentIcons.cloud_upload,
          label: '导出全部 (JSON)',
          onTap: () => _exportAll(context, ref),
        ),
        _NavItem(
          icon: FluentIcons.cloud_download,
          label: '从 JSON 导入',
          onTap: () => _importJson(context, ref),
        ),
      ],
    );
  }

  Future<void> _exportAll(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(noteRepositoryProvider);
    try {
      final path = await ImportExportService.instance.exportAllJson(repo);
      if (path == null) return;
      if (!context.mounted) return;
      _toast(context, '已导出到：\n$path');
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '导出失败：$e', error: true);
    }
  }

  Future<void> _importJson(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(noteRepositoryProvider);
    try {
      final res = await ImportExportService.instance.importJson(repo);
      if (res == null) return;
      if (!context.mounted) return;
      _toast(context, '导入成功：新增 ${res.added}、覆盖 ${res.updated}');
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, '导入失败：$e', error: true);
    }
  }

  void _toast(BuildContext context, String msg, {bool error = false}) {
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: Text(error ? '错误' : '提示'),
        content: Text(msg),
        actions: [
          FilledButton(
              child: const Text('确定'),
              onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }

  void _showAddTagDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: const Text('新建标签'),
        content: TextBox(controller: ctrl, placeholder: '标签名称'),
        actions: [
          Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('创建'),
            onPressed: () {
              final t = ctrl.text.trim();
              if (t.isNotEmpty) {
                ref.read(navSelectionProvider.notifier).state =
                    NavSelection.byTag(t);
              }
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showRenameTagSheet(
      BuildContext context, WidgetRef ref, String oldTag) {
    final ctrl = TextEditingController(text: oldTag);
    showDialog<void>(
      context: context,
      builder: (_) => ContentDialog(
        title: Text('管理标签 #$oldTag'),
        content: TextBox(controller: ctrl, placeholder: '新名称'),
        actions: [
          Button(
            child: const Text('删除标签'),
            onPressed: () async {
              await ref.read(noteRepositoryProvider).deleteTag(oldTag);
              ref.read(navSelectionProvider.notifier).state = NavSelection.all;
              if (context.mounted) Navigator.pop(context);
            },
          ),
          Button(
              child: const Text('取消'),
              onPressed: () => Navigator.pop(context)),
          FilledButton(
            child: const Text('重命名'),
            onPressed: () async {
              final t = ctrl.text.trim();
              if (t.isNotEmpty && t != oldTag) {
                await ref.read(noteRepositoryProvider).renameTag(oldTag, t);
                ref.read(navSelectionProvider.notifier).state =
                    NavSelection.byTag(t);
              }
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.background,
    this.badge,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color? background;
  final int? badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: HoverButton(
          onPressed: onTap,
          builder: (ctx, states) {
            final hover = states.isHovered;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: background ??
                    (hover
                        ? theme.resources.subtleFillColorSecondary
                        : Colors.transparent),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(icon,
                      size: 14,
                      color: selected ? theme.accentColor : null),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (badge != null && badge! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.accentColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$badge',
                        style:
                            const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF888888),
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

class _NoteListPanel extends ConsumerStatefulWidget {
  const _NoteListPanel();

  @override
  ConsumerState<_NoteListPanel> createState() => _NoteListPanelState();
}

class _NoteListPanelState extends ConsumerState<_NoteListPanel> {
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl =
        TextEditingController(text: ref.read(searchKeywordProvider));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = ref.watch(filteredNotesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);
    final nav = ref.watch(navSelectionProvider);
    final repo = ref.read(noteRepositoryProvider);

    final isTrash = nav.mode == NavMode.trash;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Expanded(
                child: TextBox(
                  controller: _searchCtrl,
                  placeholder: '搜索便签…',
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(FluentIcons.search, size: 14),
                  ),
                  onChanged: (v) =>
                      ref.read(searchKeywordProvider.notifier).state = v,
                ),
              ),
              const SizedBox(width: 8),
              if (!isTrash)
                Tooltip(
                  message: '新建便签 (Ctrl+N)',
                  child: IconButton(
                    icon: const Icon(FluentIcons.add, size: 16),
                    onPressed: () async {
                      final note = await repo.create(
                        // 在标签视图下创建便签自动带上当前标签
                        // (内容空)
                      );
                      if (nav.mode == NavMode.tag && nav.tag != null) {
                        await repo.setTags(note.id, [nav.tag!]);
                      }
                      ref.read(selectedNoteIdProvider.notifier).state =
                          note.id;
                    },
                  ),
                ),
              if (isTrash)
                Tooltip(
                  message: '清空回收站',
                  child: IconButton(
                    icon: const Icon(FluentIcons.delete, size: 16),
                    onPressed: () async {
                      final n = await repo.emptyTrash();
                      if (n > 0) {
                        ref.read(selectedNoteIdProvider.notifier).state = null;
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: notes.isEmpty
              ? Center(
                  child: Text(
                    isTrash ? '回收站为空' : '暂无便签\n点击右上角 + 新建',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF888888)),
                  ),
                )
              : Material(
                  type: MaterialType.transparency,
                  child: ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: notes.length,
                  // 回收站禁止拖拽排序
                  buildDefaultDragHandles: !isTrash,
                  onReorder: (oldIndex, newIndex) async {
                    if (isTrash) return;
                    if (notes.length < 2) return;
                    if (newIndex > oldIndex) newIndex -= 1;
                    if (oldIndex < 0 || oldIndex >= notes.length) return;
                    if (newIndex < 0) newIndex = 0;
                    if (newIndex >= notes.length) newIndex = notes.length - 1;
                    if (oldIndex == newIndex) return;
                    final ids = notes.map((n) => n.id).toList();
                    final moved = ids.removeAt(oldIndex);
                    ids.insert(newIndex, moved);
                    await repo.reorder(ids);
                  },
                  proxyDecorator: (child, _, anim) => child,
                  itemBuilder: (context, i) {
                    final note = notes[i];
                    return KeyedSubtree(
                      key: ValueKey(note.id),
                      child: NoteCard(
                        note: note,
                        selected: note.id == selectedId,
                        onTap: () => ref
                            .read(selectedNoteIdProvider.notifier)
                            .state = note.id,
                        onTogglePin: () => repo.togglePin(note.id),
                        onDelete: () async {
                          if (isTrash) {
                            await repo.hardDelete(note.id);
                          } else {
                            await repo.softDelete(note.id);
                          }
                          if (selectedId == note.id) {
                            ref.read(selectedNoteIdProvider.notifier).state =
                                null;
                          }
                        },
                        onDetach: isTrash
                            ? null
                            : () => ref
                                .read(multiWindowServiceProvider)
                                .detachNote(note, repo),
                      ),
                    );
                  },
                  ),
                ),
        ),
      ],
    );
  }
}

class _RightPane extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navSelectionProvider);
    final notes = ref.watch(filteredNotesProvider);
    final selectedId = ref.watch(selectedNoteIdProvider);

    if (nav.mode == NavMode.trash) {
      // 回收站显示恢复 / 永久删除面板
      final id = selectedId ??
          (notes.isNotEmpty ? notes.first.id : null);
      return id == null
          ? const _Empty(text: '回收站为空，没有可查看的便签')
          : TrashDetailView(noteId: id);
    }

    final id = selectedId ??
        (notes.isNotEmpty ? notes.first.id : null);
    if (id == null) {
      return const _Empty(text: '选择一个便签开始编辑');
    }
    return NoteEditorView(key: ValueKey(id), noteId: id);
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(FluentIcons.edit_note, size: 64, color: Color(0xFFBBBBBB)),
          const SizedBox(height: 12),
          Text(text,
              style: const TextStyle(color: Color(0xFF888888), fontSize: 14)),
        ],
      ),
    );
  }
}
