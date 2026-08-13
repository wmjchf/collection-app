class SystemFilter {
  const SystemFilter({
    required this.id,
    required this.code,
    required this.name,
    required this.itemCount,
    required this.countLabel,
    required this.sortOrder,
  });

  final int id;
  final String code;
  final String name;
  final int itemCount;
  final String countLabel;
  final int sortOrder;

  factory SystemFilter.fromJson(Map<String, dynamic> json) {
    return SystemFilter(
      id: (json['id'] as num).toInt(),
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      countLabel: json['countLabel'] as String? ?? '0',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );
  }
}
