class AiOrganizeTagBrief {
  const AiOrganizeTagBrief({
    required this.id,
    required this.name,
  });

  final int id;
  final String name;

  factory AiOrganizeTagBrief.fromJson(Map<String, dynamic> json) {
    return AiOrganizeTagBrief(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
    );
  }
}

class AiOrganizeModuleProposal {
  const AiOrganizeModuleProposal({
    required this.name,
    required this.tagIds,
    required this.tags,
    this.existingModuleId,
  });

  final String name;
  final int? existingModuleId;
  final List<int> tagIds;
  final List<AiOrganizeTagBrief> tags;

  bool get isNew => existingModuleId == null;

  factory AiOrganizeModuleProposal.fromJson(Map<String, dynamic> json) {
    final tagIds = (json['tagIds'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final tags = (json['tags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiOrganizeTagBrief.fromJson)
        .toList();
    final existing = json['existingModuleId'];
    return AiOrganizeModuleProposal(
      name: json['name'] as String? ?? '',
      existingModuleId:
          existing == null ? null : (existing as num).toInt(),
      tagIds: tagIds,
      tags: tags.isNotEmpty
          ? tags
          : tagIds
              .map((id) => AiOrganizeTagBrief(id: id, name: '#$id'))
              .toList(),
    );
  }

  Map<String, dynamic> toApplyJson() => {
        'name': name,
        'existingModuleId': existingModuleId,
        'tagIds': tagIds,
      };
}

class AiOrganizeProposal {
  const AiOrganizeProposal({
    required this.modules,
    required this.ungroupedTagIds,
    required this.ungroupedTags,
    required this.creditsUsed,
    this.generatedAt,
  });

  final List<AiOrganizeModuleProposal> modules;
  final List<int> ungroupedTagIds;
  final List<AiOrganizeTagBrief> ungroupedTags;
  final int creditsUsed;
  final String? generatedAt;

  factory AiOrganizeProposal.fromJson(Map<String, dynamic> json) {
    final ungroupedIds = (json['ungroupedTagIds'] as List<dynamic>? ?? const [])
        .map((e) => (e as num).toInt())
        .toList();
    final ungroupedTags = (json['ungroupedTags'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AiOrganizeTagBrief.fromJson)
        .toList();
    return AiOrganizeProposal(
      modules: (json['modules'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(AiOrganizeModuleProposal.fromJson)
          .toList(),
      ungroupedTagIds: ungroupedIds,
      ungroupedTags: ungroupedTags.isNotEmpty
          ? ungroupedTags
          : ungroupedIds
              .map((id) => AiOrganizeTagBrief(id: id, name: '#$id'))
              .toList(),
      creditsUsed: (json['creditsUsed'] as num?)?.toInt() ?? 0,
      generatedAt: json['generatedAt'] as String?,
    );
  }

  Map<String, dynamic> toApplyBody() => {
        'modules': modules.map((m) => m.toApplyJson()).toList(),
        'ungroupedTagIds': ungroupedTagIds,
      };
}
