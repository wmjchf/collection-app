class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.itemCount,
    required this.sortOrder,
    this.code,
    this.parentId,
  });

  final int id;
  final String name;
  final String? code;
  final bool isSystem;
  final int itemCount;
  final int sortOrder;
  /// 一层父标签；仅整理视图使用，打标仍扁平。
  final int? parentId;

  String get countLabel => '$itemCount';

  Tag copyWith({
    int? id,
    String? name,
    String? code,
    bool? isSystem,
    int? itemCount,
    int? sortOrder,
    int? parentId,
    bool clearParentId = false,
  }) {
    return Tag(
      id: id ?? this.id,
      name: name ?? this.name,
      code: code ?? this.code,
      isSystem: isSystem ?? this.isSystem,
      itemCount: itemCount ?? this.itemCount,
      sortOrder: sortOrder ?? this.sortOrder,
      parentId: clearParentId ? null : (parentId ?? this.parentId),
    );
  }

  factory Tag.fromJson(Map<String, dynamic> json) {
    return Tag(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      parentId: (json['parentId'] as num?)?.toInt(),
    );
  }
}

/// 按父级分组后的扁平展示行（一层）。
List<Tag> flattenTagsForDisplay(List<Tag> tags) {
  final roots = tags.where((t) => t.parentId == null).toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final byParent = <int, List<Tag>>{};
  for (final t in tags) {
    final p = t.parentId;
    if (p == null) continue;
    (byParent[p] ??= []).add(t);
  }
  for (final list in byParent.values) {
    list.sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }
  final out = <Tag>[];
  for (final root in roots) {
    out.add(root);
    out.addAll(byParent[root.id] ?? const []);
  }
  // 父级已删的孤儿：提到根级展示
  final shown = out.map((t) => t.id).toSet();
  for (final t in tags) {
    if (!shown.contains(t.id)) out.add(t);
  }
  return out;
}
