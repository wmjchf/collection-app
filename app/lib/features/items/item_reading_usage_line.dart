import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_usage_models.dart';

/// 阅读页：本篇本月 AI / 转写用量与预估积分（muted 单行/多行）。
class ItemReadingUsageLine extends StatelessWidget {
  const ItemReadingUsageLine({super.key, required this.usage});

  final ItemUsageSnapshot usage;

  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    if (!usage.show) return const SizedBox.shrink();

    final parts = <String>[];
    if (usage.aiCredits > 0) {
      parts.add('AI 已用 ${usage.aiCredits} 积分');
      final detail = _featureDetail(usage.byFeature);
      if (detail.isNotEmpty) parts.add(detail);
    }
    if (usage.transcriptMinutes > 0) {
      parts.add('转写 ${_fmtMinutes(usage.transcriptMinutes)}');
    }

    final est = usage.estimate;
    if (est != null) {
      final estParts = <String>[];
      if (usage.byFeature['summary']?.credits == 0 &&
          est.summary.credits > 0) {
        estParts.add('总结约 ${est.summary.credits}');
      }
      if (usage.byFeature['tags']?.credits == 0 && est.tags.credits > 0) {
        estParts.add('标签约 ${est.tags.credits}');
      }
      if (usage.byFeature['mindmap']?.credits == 0 &&
          est.mindmap.credits > 0) {
        estParts.add('脑图约 ${est.mindmap.credits}');
      }
      if (estParts.isNotEmpty) {
        parts.add('预估 ${estParts.join(' · ')} 积分/次');
      } else if (usage.aiCredits == 0 && est.fullStack.credits > 0) {
        parts.add('预估全套 AI 约 ${est.fullStack.credits} 积分');
      }
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    final month = usage.yearMonth.isEmpty ? '' : '（${usage.yearMonth}）';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        '本篇用量$month：${parts.join(' · ')}',
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: _muted,
        ),
      ),
    );
  }

  String _featureDetail(Map<String, ItemFeatureUsage> byFeature) {
    final bits = <String>[];
    for (final entry in [
      ('总结', 'summary'),
      ('标签', 'tags'),
      ('脑图', 'mindmap'),
    ]) {
      final c = byFeature[entry.$2]?.credits ?? 0;
      if (c > 0) bits.add('${entry.$1} $c');
    }
    if (bits.isEmpty) return '';
    return bits.join(' / ');
  }

  String _fmtMinutes(double m) {
    if (m < 1) return '${(m * 60).round()} 秒';
    if (m == m.roundToDouble()) return '${m.round()} 分钟';
    return '${m.toStringAsFixed(1)} 分钟';
  }
}
