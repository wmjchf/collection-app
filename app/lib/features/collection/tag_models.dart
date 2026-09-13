class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.itemCount,
    required this.sortOrder,
    this.code,
    this.moduleId,
  });

  final int id;
  final String name;
  final String? code;
  final bool isSystem;
  final int itemCount;
  final int sortOrder;
  final int? moduleId;

  String get countLabel => '$itemCount';

  factory Tag.fromJson(Map<String, dynamic> json) {
    final mid = json['moduleId'];
    return Tag(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      moduleId: mid == null ? null : (mid as num).toInt(),
    );
  }

  Tag copyWith({int? moduleId, bool clearModuleId = false}) {
    return Tag(
      id: id,
      name: name,
      code: code,
      isSystem: isSystem,
      itemCount: itemCount,
      sortOrder: sortOrder,
      moduleId: clearModuleId ? null : (moduleId ?? this.moduleId),
    );
  }
}
