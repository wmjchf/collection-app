/// 动态预设缓存键：只依赖稳定字段，避免进页指纹抖动导致 miss。
class AgentPresetCache {
  AgentPresetCache._();

  static String cacheKey({
    required int userId,
    int? focusItemId,
    required int conversationId,
    required int lastAssistantId,
    required bool hasSuccessfulTranscript,
  }) {
    final scope = focusItemId != null ? 'item_$focusItemId' : 'global';
    final tx = hasSuccessfulTranscript ? 1 : 0;
    return 'agent_presets_v2_${userId}_${scope}_c${conversationId}_a${lastAssistantId}_t$tx';
  }
}
