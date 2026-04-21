import 'dart:convert';

enum NoteType { text, checklist }

class ChecklistItem {
  final String text;
  final bool done;

  const ChecklistItem({required this.text, this.done = false});

  ChecklistItem copyWith({String? text, bool? done}) =>
      ChecklistItem(text: text ?? this.text, done: done ?? this.done);

  Map<String, Object?> toJson() => {'t': text, 'd': done};

  factory ChecklistItem.fromJson(Map<String, Object?> json) => ChecklistItem(
        text: (json['t'] as String?) ?? '',
        done: (json['d'] as bool?) ?? false,
      );
}

class Note {
  final int id;
  final int folderId;
  final NoteType type;
  final String title;
  final String content;
  final int bgColor;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? alertAt;
  final bool isPinned;
  final bool isDeleted;

  const Note({
    this.id = 0,
    this.folderId = 0,
    this.type = NoteType.text,
    this.title = '',
    this.content = '',
    this.bgColor = 0,
    required this.createdAt,
    required this.modifiedAt,
    this.alertAt,
    this.isPinned = false,
    this.isDeleted = false,
  });

  Note copyWith({
    int? id,
    int? folderId,
    NoteType? type,
    String? title,
    String? content,
    int? bgColor,
    DateTime? createdAt,
    DateTime? modifiedAt,
    DateTime? alertAt,
    bool clearAlert = false,
    bool? isPinned,
    bool? isDeleted,
  }) {
    return Note(
      id: id ?? this.id,
      folderId: folderId ?? this.folderId,
      type: type ?? this.type,
      title: title ?? this.title,
      content: content ?? this.content,
      bgColor: bgColor ?? this.bgColor,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      alertAt: clearAlert ? null : (alertAt ?? this.alertAt),
      isPinned: isPinned ?? this.isPinned,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'folder_id': folderId,
      'type': type.index,
      'title': title,
      'content': content,
      'bg_color': bgColor,
      'created_at': createdAt.millisecondsSinceEpoch,
      'modified_at': modifiedAt.millisecondsSinceEpoch,
      'alert_at': alertAt?.millisecondsSinceEpoch ?? 0,
      'is_pinned': isPinned ? 1 : 0,
      'is_deleted': isDeleted ? 1 : 0,
    };
  }

  factory Note.fromMap(Map<String, Object?> map) {
    final alertMs = (map['alert_at'] as int?) ?? 0;
    return Note(
      id: map['id'] as int,
      folderId: (map['folder_id'] as int?) ?? 0,
      type: NoteType.values[(map['type'] as int?) ?? 0],
      title: (map['title'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
      bgColor: (map['bg_color'] as int?) ?? 0,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modified_at'] as int?) ?? 0),
      alertAt: alertMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(alertMs)
          : null,
      isPinned: ((map['is_pinned'] as int?) ?? 0) == 1,
      isDeleted: ((map['is_deleted'] as int?) ?? 0) == 1,
    );
  }

  List<ChecklistItem> get checklistItems {
    if (type != NoteType.checklist || content.isEmpty) return const [];
    try {
      final list = jsonDecode(content) as List<dynamic>;
      return list
          .map((e) => ChecklistItem.fromJson(e as Map<String, Object?>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static String encodeChecklist(List<ChecklistItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  String previewText() {
    if (type == NoteType.text) {
      return content.trim();
    }
    final items = checklistItems;
    if (items.isEmpty) return '';
    return items
        .map((e) => '${e.done ? '☑' : '☐'} ${e.text}')
        .join('\n');
  }
}
