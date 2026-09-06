import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_usage_models.dart';

/// 阅读页：预估本篇 AI 单次全套用量（muted 单行）。
class ItemReadingUsageLine extends StatelessWidget {
  const ItemReadingUsageLine({super.key, required this.estimate});

  final ItemAiEstimate estimate;

  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    if (!estimate.show || estimate.estimateCredits <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text(
        '预估本次 AI 约 ${estimate.estimateCredits} 积分',
        style: const TextStyle(
          fontSize: 12,
          height: 1.45,
          color: _muted,
        ),
      ),
    );
  }
}
