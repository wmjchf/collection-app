import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_transcript_page.dart';
import 'package:super_collection/features/items/transcript_models.dart';

/// 挂在播放器下方：loading / 失败提示；成功态为可点击预览，跳转文稿页
class TranscriptSegmentPanel extends StatelessWidget {
  const TranscriptSegmentPanel({
    super.key,
    required this.segment,
    this.hidePendingLoading = false,
  });

  final TranscriptSegment? segment;
  /// 思维导图触发的自动转写时，进度已在脑图卡片展示，不重复显示 pending UI
  final bool hidePendingLoading;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _transcriptText = Color(0xFF3A404C);
  static const _surface = Color(0xFFF3F6FA);

  void _openTranscriptPage(BuildContext context, TranscriptSegment seg) {
    final text = (seg.text ?? '').trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemTranscriptPage(
          text: text,
          cues: seg.cues,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seg = segment;
    if (seg == null || seg.status == 'none') return const SizedBox.shrink();

    if (seg.isPending) {
      if (hidePendingLoading) return const SizedBox.shrink();
      final label = (seg.phaseLabel ?? '').trim();
      final title = label.isEmpty ? '文稿转写中…' : label;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '转写进度仅显示在当前视频下方',
              style: TextStyle(
                fontSize: 12,
                color: _muted.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    if (seg.isFailed) {
      final err = (seg.error ?? '').trim();
      if (err.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          '文稿转写失败：$err',
          style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
        ),
      );
    }

    if (!seg.hasText) return const SizedBox.shrink();

    final text = seg.text!.trim();
    final charCount = text.replaceAll(RegExp(r'\s'), '').length;
    final metaLabel = charCount > 0 ? '· $charCount 字' : '· 已转写';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '文稿',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              Text(
                ' $metaLabel',
                style: const TextStyle(fontSize: 12, color: _muted),
              ),
              const Spacer(),
              Text(
                '查看全文',
                style: TextStyle(fontSize: 12, color: _brand),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Material(
            color: _surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _openTranscriptPage(context, seg),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 3, color: _brand),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.55,
                            color: _transcriptText,
                          ),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: _muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
