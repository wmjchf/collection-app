class ItemFeatureUsage {
  const ItemFeatureUsage({required this.tokens, required this.credits});

  final int tokens;
  final int credits;

  factory ItemFeatureUsage.fromJson(Map<String, dynamic>? json) {
    return ItemFeatureUsage(
      tokens: (json?['tokens'] as num?)?.toInt() ?? 0,
      credits: (json?['credits'] as num?)?.toInt() ?? 0,
    );
  }
}

class ItemUsageEstimate {
  const ItemUsageEstimate({
    required this.summary,
    required this.tags,
    required this.mindmap,
    required this.fullStack,
  });

  final ItemFeatureUsage summary;
  final ItemFeatureUsage tags;
  final ItemFeatureUsage mindmap;
  final ItemFeatureUsage fullStack;

  factory ItemUsageEstimate.fromJson(Map<String, dynamic> json) {
    return ItemUsageEstimate(
      summary: ItemFeatureUsage.fromJson(
        json['summary'] as Map<String, dynamic>?,
      ),
      tags: ItemFeatureUsage.fromJson(json['tags'] as Map<String, dynamic>?),
      mindmap: ItemFeatureUsage.fromJson(
        json['mindmap'] as Map<String, dynamic>?,
      ),
      fullStack: ItemFeatureUsage.fromJson(
        json['fullStack'] as Map<String, dynamic>?,
      ),
    );
  }
}

class ItemUsageSnapshot {
  const ItemUsageSnapshot({
    required this.yearMonth,
    required this.show,
    required this.aiCredits,
    required this.transcriptMinutes,
    required this.byFeature,
    this.estimate,
  });

  final String yearMonth;
  final bool show;
  final int aiCredits;
  final double transcriptMinutes;
  final Map<String, ItemFeatureUsage> byFeature;
  final ItemUsageEstimate? estimate;

  factory ItemUsageSnapshot.fromJson(Map<String, dynamic> json) {
    final used = json['used'] as Map<String, dynamic>? ?? {};
    final byRaw = used['byFeature'] as Map<String, dynamic>? ?? {};
    final byFeature = <String, ItemFeatureUsage>{};
    for (final key in ['summary', 'tags', 'mindmap']) {
      byFeature[key] = ItemFeatureUsage.fromJson(
        byRaw[key] as Map<String, dynamic>?,
      );
    }
    final estRaw = json['estimate'];
    return ItemUsageSnapshot(
      yearMonth: (json['period'] as Map<String, dynamic>?)?['yearMonth']
              as String? ??
          '',
      show: json['show'] == true,
      aiCredits: (used['aiCredits'] as num?)?.toInt() ?? 0,
      transcriptMinutes: (used['transcriptMinutes'] as num?)?.toDouble() ?? 0,
      byFeature: byFeature,
      estimate: estRaw is Map<String, dynamic>
          ? ItemUsageEstimate.fromJson(estRaw)
          : null,
    );
  }
}
