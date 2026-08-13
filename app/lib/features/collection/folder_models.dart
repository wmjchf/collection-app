class Folder {
  const Folder({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.itemCount,
    required this.sortOrder,
    this.code,
  });

  final int id;
  final String name;
  final String? code;
  final bool isSystem;
  final int itemCount;
  final int sortOrder;

  String get countLabel => '$itemCount';

  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      code: json['code'] as String?,
      isSystem: json['isSystem'] as bool? ?? false,
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
