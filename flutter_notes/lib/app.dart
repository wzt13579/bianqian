import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/notes_repository.dart';
import 'state/notes_store.dart';
import 'ui/pages/notes_list_page.dart';
import 'ui/theme/app_theme.dart';

class MiNotesApp extends StatelessWidget {
  const MiNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => NotesStore(NotesRepository())..bootstrap(),
      child: MaterialApp(
        title: 'MI 便签',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const NotesListPage(),
      ),
    );
  }
}
