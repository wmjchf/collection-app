import 'package:super_collection/features/collection/tag_models.dart';

class TagModule {
  const TagModule({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.tags,
  });

  final int id;
  final String name;
  final int sortOrder;
  final List<Tag> tags;

  factory TagModule.fromJson(Map<String, dynamic> json) {
    final list = json['tags'] as List<dynamic>? ?? const [];
    return TagModule(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      tags: list
          .whereType<Map<String, dynamic>>()
          .map(Tag.fromJson)
          .toList(),
    );
  }

  TagModule copyWith({List<Tag>? tags}) {
    return TagModule(
      id: id,
      name: name,
      sortOrder: sortOrder,
      tags: tags ?? this.tags,
    );
  }
}
