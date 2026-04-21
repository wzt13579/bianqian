class Folder {
  static const int rootId = 0;
  static const int callRecordsId = -1;

  final int id;
  final String name;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final int position;

  const Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
    this.position = 0,
  });

  Folder copyWith({
    int? id,
    String? name,
    DateTime? createdAt,
    DateTime? modifiedAt,
    int? position,
  }) {
    return Folder(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      position: position ?? this.position,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != 0) 'id': id,
      'name': name,
      'created_at': createdAt.millisecondsSinceEpoch,
      'modified_at': modifiedAt.millisecondsSinceEpoch,
      'position': position,
    };
  }

  factory Folder.fromMap(Map<String, Object?> map) {
    return Folder(
      id: map['id'] as int,
      name: (map['name'] as String?) ?? '',
      createdAt:
          DateTime.fromMillisecondsSinceEpoch((map['created_at'] as int?) ?? 0),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(
          (map['modified_at'] as int?) ?? 0),
      position: (map['position'] as int?) ?? 0,
    );
  }
}
