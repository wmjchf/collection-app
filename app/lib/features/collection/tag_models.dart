class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.itemCount,
    required this.sortOrder,
    this.code,
    this.moduleId,
    this.parentId,
    this.description,
  });

  final int id;
  final String name;
  final String? description;
  final String? code;
  final bool isSystem;
  final int itemCount;
  final int sortOrder;

  /// 直接父标签；与 [parentId] 同源（兼容旧字段 moduleId）
  final int? moduleId;
  final int? parentId;

  int? get effectiveParentId => parentId ?? moduleId;

  String get countLabel => '$itemCount';

  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  factory Tag.fromJson(Map<String, dynamic> json) {
    final mid = json['moduleId'];
    final pid = json['parentId'] ?? mid;
    final desc = json['description'] as String?;
    final parent = pid == null ? null : (pid as num).toInt();
    return Tag(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: (desc == null || desc.trim().isEmpty) ? null : desc.trim(),
      code: json['code'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      parentId: parent,
      moduleId: parent,
    );
  }

  Tag copyWith({
    int? moduleId,
    int? parentId,
    bool clearModuleId = false,
    bool clearParentId = false,
    String? description,
    bool clearDescription = false,
  }) {
    final nextParent = clearParentId || clearModuleId
        ? null
        : (parentId ?? this.parentId ?? moduleId ?? this.moduleId);
    return Tag(
      id: id,
      name: name,
      description: clearDescription
          ? null
          : (description ?? this.description),
      code: code,
      isSystem: isSystem,
      itemCount: itemCount,
      sortOrder: sortOrder,
      parentId: nextParent,
      moduleId: nextParent,
    );
  }
}
