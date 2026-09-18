class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.itemCount,
    required this.sortOrder,
    this.code,
    this.moduleId,
    this.description,
  });

  final int id;
  final String name;
  final String? description;
  final String? code;
  final bool isSystem;
  final int itemCount;
  final int sortOrder;
  final int? moduleId;

  String get countLabel => '$itemCount';

  bool get hasDescription =>
      description != null && description!.trim().isNotEmpty;

  factory Tag.fromJson(Map<String, dynamic> json) {
    final mid = json['moduleId'];
    final desc = json['description'] as String?;
    return Tag(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      description: (desc == null || desc.trim().isEmpty) ? null : desc.trim(),
      code: json['code'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      moduleId: mid == null ? null : (mid as num).toInt(),
    );
  }

  Tag copyWith({
    int? moduleId,
    bool clearModuleId = false,
    String? description,
    bool clearDescription = false,
  }) {
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
      moduleId: clearModuleId ? null : (moduleId ?? this.moduleId),
    );
  }
}
