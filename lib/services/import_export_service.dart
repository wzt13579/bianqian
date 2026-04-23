import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/note.dart';
import 'note_repository.dart';

/// 数据导入 / 导出。
///
/// - 导出：所有便签打包为 JSON（`bianqian_export_xxx.json`）。
/// - 导出单条：转成 Markdown（`*.md`）。
/// - 导入：解析 JSON，按 id upsert 到 Hive；冲突默认覆盖。
class ImportExportService {
  ImportExportService._();
  static final ImportExportService instance = ImportExportService._();

  static const int _schemaVersion = 1;

  // ============== 导出 ==============

  /// 导出全部便签到用户选择的 JSON 文件。返回文件路径（取消则为 null）。
  Future<String?> exportAllJson(NoteRepository repo) async {
    final notes = repo.getAll(includeDeleted: true);
    final payload = <String, dynamic>{
      'app': 'bianqian',
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'count': notes.length,
      'notes': notes.map((n) => n.toJson()).toList(),
    };
    final jsonStr = const JsonEncoder.withIndent('  ').convert(payload);

    final fileName =
        'bianqian_export_${DateTime.now().millisecondsSinceEpoch}.json';
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出便签数据',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (outputPath == null) return null;
    final file = File(outputPath);
    await file.writeAsString(jsonStr, flush: true);
    return outputPath;
  }

  /// 把单条便签导出为 Markdown 文件。
  Future<String?> exportNoteMarkdown(Note note) async {
    final buf = StringBuffer()
      ..writeln('# ${note.title.isEmpty ? "(无标题)" : note.title}')
      ..writeln()
      ..writeln('> 创建于 ${note.createTime.toIso8601String()}  ')
      ..writeln('> 更新于 ${note.updateTime.toIso8601String()}  ');
    if (note.tags.isNotEmpty) {
      buf.writeln('> 标签：${note.tags.map((t) => "`#$t`").join(" ")}');
    }
    buf
      ..writeln()
      ..writeln('---')
      ..writeln()
      ..writeln(note.content);

    final safeTitle = (note.title.isEmpty ? 'note' : note.title)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: '导出便签',
      fileName: '$safeTitle.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
    if (outputPath == null) return null;
    await File(outputPath).writeAsString(buf.toString(), flush: true);
    return outputPath;
  }

  // ============== 导入 ==============

  /// 选择 JSON 文件并导入。返回 (新增数, 覆盖数)。
  Future<({int added, int updated})?> importJson(
    NoteRepository repo, {
    bool overwrite = true,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择便签 JSON 文件',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null) return null;

    final raw = await File(path).readAsString();
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final list = (map['notes'] as List).cast<Map<String, dynamic>>();

    int added = 0, updated = 0;
    for (final j in list) {
      final n = Note.fromJson(j);
      final existing = repo.getById(n.id);
      if (existing == null) {
        // 借助 box 直接 put，绕过 create() 自动生成 id
        await repo.upsertRaw(n);
        added++;
      } else if (overwrite) {
        await repo.upsertRaw(n);
        updated++;
      }
    }
    return (added: added, updated: updated);
  }
}
