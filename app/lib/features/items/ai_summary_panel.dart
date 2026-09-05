import 'package:flutter/material.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';

/// 阅读页正文下方：AI 总结 loading / 结果 / 失败
class AiSummaryPanel extends StatelessWidget {
  const AiSummaryPanel({
    super.key,
    required this.summaryMeta,
    this.onRetry,
  });

  final AiSummaryMeta summaryMeta;
  final VoidCallback? onRetry;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _surface = Color(0xFFF3F6FA);

  @override
  Widget build(BuildContext context) {
    final meta = summaryMeta;
    if (meta.status == 'none' || meta.status == 'skipped') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _SummaryLoadingCard(awaitTranscript: meta.awaitTranscript),
      );
    }

    if (meta.isFailed) {
      final err = (meta.error ?? '').trim();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI 总结',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                err.isEmpty ? 'AI 总结生成失败' : 'AI 总结失败：$err',
                style: const TextStyle(
                  fontSize: 13,
                  color: _muted,
                  height: 1.4,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onRetry,
                  child: const Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!meta.hasText) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'AI 总结',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _text,
                    ),
                  ),
                ),
                if (onRetry != null)
                  GestureDetector(
                    onTap: onRetry,
                    child: const Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: _muted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              meta.text!.trim(),
              style: const TextStyle(
                fontSize: 15,
                color: _text,
                height: 1.65,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AiSummaryPanel._surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _SummaryLoadingCard extends StatelessWidget {
  const _SummaryLoadingCard({this.awaitTranscript = false});

  final bool awaitTranscript;

  @override
  Widget build(BuildContext context) {
    final label = awaitTranscript ? '转写完成后生成 AI 总结…' : 'AI 总结生成中…';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: AiSummaryPanel._surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AiSummaryPanel._brand.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AiSummaryPanel._muted.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
