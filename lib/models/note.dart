import 'package:hive/hive.dart';

/// 便签实体模型。
///
/// 使用 Hive 进行本地持久化存储。这里同时手写 [NoteAdapter]，
/// 避免开发环境必须先运行 `build_runner` 才能编译。
/// 如需切换到自动生成，可加 `@HiveType(typeId: 0)` 注解并运行：
///   `dart run build_runner build --delete-conflicting-outputs`
class Note extends HiveObject {
  final String id;

  String title;

  /// 富文本/Markdown 原始内容。
  String content;

  /// 便签背景色 (ARGB int)。便于 Hive 直接存储。
  int color;

  bool isPinned;

  DateTime? reminderTime;

  DateTime createTime;

  DateTime updateTime;

  /// 标签 / 分类，便于二级分类系统。
  List<String> tags;

  /// 是否已被删除（软删除，便于回收站功能）。
  bool isDeleted;

  /// 是否分离为独立桌面窗口。
  bool isDetached;

  /// 拖拽排序索引（数值越小越靠前；新便签默认取当前最大值 +1）。
  /// 仅作用于"全部便签"视图的同 isPinned 分组内。
  int sortIndex;

  Note({
    required this.id,
    this.title = '',
    this.content = '',
    this.color = 0xFFFFF8DC, // 默认: 米黄色
    this.isPinned = false,
    this.reminderTime,
    required this.createTime,
    required this.updateTime,
    List<String>? tags,
    this.isDeleted = false,
    this.isDetached = false,
    this.sortIndex = 0,
  }) : tags = tags ?? <String>[];

  Note copyWith({
    String? title,
    String? content,
    int? color,
    bool? isPinned,
    DateTime? reminderTime,
    DateTime? updateTime,
    List<String>? tags,
    bool? isDeleted,
    bool? isDetached,
    int? sortIndex,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      isPinned: isPinned ?? this.isPinned,
      reminderTime: reminderTime ?? this.reminderTime,
      createTime: createTime,
      updateTime: updateTime ?? DateTime.now(),
      tags: tags ?? List<String>.from(this.tags),
      isDeleted: isDeleted ?? this.isDeleted,
      isDetached: isDetached ?? this.isDetached,
      sortIndex: sortIndex ?? this.sortIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'content': content,
        'color': color,
        'isPinned': isPinned,
        'reminderTime': reminderTime?.toIso8601String(),
        'createTime': createTime.toIso8601String(),
        'updateTime': updateTime.toIso8601String(),
        'tags': tags,
        'isDeleted': isDeleted,
        'isDetached': isDetached,
        'sortIndex': sortIndex,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        content: (j['content'] as String?) ?? '',
        color: (j['color'] as int?) ?? 0xFFFFF8DC,
        isPinned: (j['isPinned'] as bool?) ?? false,
        reminderTime: j['reminderTime'] == null
            ? null
            : DateTime.parse(j['reminderTime'] as String),
        createTime: DateTime.parse(j['createTime'] as String),
        updateTime: DateTime.parse(j['updateTime'] as String),
        tags: (j['tags'] as List?)?.cast<String>() ?? <String>[],
        isDeleted: (j['isDeleted'] as bool?) ?? false,
        isDetached: (j['isDetached'] as bool?) ?? false,
        sortIndex: (j['sortIndex'] as int?) ?? 0,
      );
}
