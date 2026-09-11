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
  /// 父标签；整理建树、选标签缩进；打标写入时会连带祖先，展示只显示最深勾选层。
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

int _tagSort(Tag a, Tag b) {
  final c = a.sortOrder.compareTo(b.sortOrder);
  return c != 0 ? c : a.id.compareTo(b.id);
}

/// parentId → 直接子标签（已按 sortOrder 排序）
Map<int, List<Tag>> tagChildrenByParent(List<Tag> tags) {
  final byParent = <int, List<Tag>>{};
  for (final t in tags) {
    final p = t.parentId;
    if (p == null) continue;
    (byParent[p] ??= []).add(t);
  }
  for (final list in byParent.values) {
    list.sort(_tagSort);
  }
  return byParent;
}

/// DFS 前序扁平展示行（任意多层）。
List<Tag> flattenTagsForDisplay(List<Tag> tags) {
  final byParent = tagChildrenByParent(tags);
  final roots = tags.where((t) => t.parentId == null).toList()..sort(_tagSort);
  final out = <Tag>[];
  final visiting = <int>{};

  void walk(Tag node) {
    if (!visiting.add(node.id)) return; // 防环
    out.add(node);
    for (final child in byParent[node.id] ?? const <Tag>[]) {
      walk(child);
    }
    visiting.remove(node.id);
  }

  for (final root in roots) {
    walk(root);
  }

  // 孤儿（父级缺失或成环截断）：按原序补到末尾
  final shown = out.map((t) => t.id).toSet();
  for (final t in tags) {
    if (!shown.contains(t.id)) out.add(t);
  }
  return out;
}

/// 节点路径文案：根 › … › 自身。
String tagPathLabel(Tag tag, Map<int, Tag> byId, {String sep = ' › '}) {
  final parts = <String>[tag.name];
  var cur = tag.parentId;
  final seen = <int>{tag.id};
  while (cur != null) {
    if (!seen.add(cur)) break;
    final p = byId[cur];
    if (p == null) break;
    parts.insert(0, p.name);
    cur = p.parentId;
    if (parts.length > 64) break;
  }
  return parts.join(sep);
}

/// 节点深度：根 = 0。
int tagDepth(Tag tag, Map<int, Tag> byId) {
  var depth = 0;
  var cur = tag.parentId;
  final seen = <int>{tag.id};
  while (cur != null) {
    if (!seen.add(cur)) break;
    depth += 1;
    cur = byId[cur]?.parentId;
    if (depth > 64) break;
  }
  return depth;
}

/// 在已选 id 中，去掉「另有更深层后代也被选中」的祖先，仅保留最深展示层。
///
/// [allTags] 提供完整 `parentId` 关系（通常为用户全部标签）。
Set<int> leafTagIdsAmong(Iterable<int> selectedIds, List<Tag> allTags) {
  final ids = selectedIds.toSet();
  if (ids.isEmpty) return {};
  final byId = {for (final t in allTags) t.id: t};

  bool hasSelectedDescendant(int id) {
    for (final otherId in ids) {
      if (otherId == id) continue;
      var cur = byId[otherId]?.parentId;
      final seen = <int>{};
      while (cur != null && seen.add(cur)) {
        if (cur == id) return true;
        cur = byId[cur]?.parentId;
      }
    }
    return false;
  }

  return {
    for (final id in ids)
      if (!hasSelectedDescendant(id)) id,
  };
}

/// 条目已关联标签中，仅保留展示用的最深层（祖先已写入但不展示）。
List<Tag> leafTagsAmong(List<Tag> tags) {
  if (tags.isEmpty) return const [];
  final leafIds = leafTagIdsAmong(tags.map((t) => t.id), tags);
  final out = [for (final t in tags) if (leafIds.contains(t.id)) t];
  out.sort(_tagSort);
  return out;
}

/// [id] 的全部后代（不含自身）。
Set<int> tagDescendantIds(int id, Map<int, List<Tag>> childrenByParent) {
  final out = <int>{};
  void walk(int pid) {
    for (final c in childrenByParent[pid] ?? const <Tag>[]) {
      if (out.add(c.id)) walk(c.id);
    }
  }

  walk(id);
  return out;
}

/// 在已扁平的展示行中，从 [startIndex] 起取「节点 + 连续后代」块。
List<Tag> tagSubtreeBlock(List<Tag> rows, int startIndex) {
  if (startIndex < 0 || startIndex >= rows.length) return const [];
  final root = rows[startIndex];
  final byParent = tagChildrenByParent(rows);
  final desc = tagDescendantIds(root.id, byParent);
  final block = <Tag>[root];
  for (var i = startIndex + 1; i < rows.length; i++) {
    if (desc.contains(rows[i].id)) {
      block.add(rows[i]);
    } else {
      break;
    }
  }
  return block;
}
