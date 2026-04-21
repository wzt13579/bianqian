import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/note.dart';
import '../../state/notes_store.dart';
import '../widgets/note_card.dart';
import 'note_edit_page.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  List<Note> _results = const [];
  bool _searched = false;

  Future<void> _runSearch(String kw) async {
    if (kw.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    final list = await context.read<NotesStore>().search(kw.trim());
    if (!mounted) return;
    setState(() {
      _results = list;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索便签...',
            border: InputBorder.none,
          ),
          onChanged: _runSearch,
          onSubmitted: _runSearch,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () {
              _controller.clear();
              _runSearch('');
            },
          ),
        ],
      ),
      body: _results.isEmpty
          ? Center(
              child: Text(_searched ? '没有找到结果' : '输入关键字搜索便签'),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final n = _results[i];
                return NoteCard(
                  note: n,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NoteEditPage(noteId: n.id),
                      ),
                    );
                    _runSearch(_controller.text);
                  },
                  onLongPress: () {},
                );
              },
            ),
    );
  }
}
