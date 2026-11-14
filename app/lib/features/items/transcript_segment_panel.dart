import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/features/items/item_transcript_page.dart';
import 'package:super_collection/features/items/reading_font_prefs.dart';
import 'package:super_collection/features/items/transcript_models.dart';

/// 转写 pending 步骤条（准备 / 提交 / 识别）；阅读页与助手共用。
class TranscriptPendingProgress extends StatefulWidget {
  const TranscriptPendingProgress({super.key, required this.segment});

  final TranscriptSegment segment;

  @override
  State<TranscriptPendingProgress> createState() =>
      _TranscriptPendingProgressState();
}

class _TranscriptPendingProgressState extends State<TranscriptPendingProgress> {
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);

  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _stepIndex {
    switch (widget.segment.phase) {
      case 'queued':
      case 'checking':
      case 'downloading':
      case 'uploading':
        return 0;
      case 'submitting':
        return 1;
      case 'queueing':
      case 'recognizing':
        return 2;
      default:
        return 0;
    }
  }

  String _elapsedLabel() {
    final at = widget.segment.phaseAt;
    if (at == null) return '';
    final sec = DateTime.now().difference(at.toLocal()).inSeconds;
    if (sec < 0) return '';
    final m = sec ~/ 60;
    final s = sec % 60;
    if (m <= 0) return '本阶段已等待 ${s}s';
    return '本阶段已等待 $m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final seg = widget.segment;
    final label = (seg.phaseLabel ?? '').trim();
    final title = label.isEmpty ? '正在生成文稿…' : label;
    final hint = (seg.phaseHint ?? '').trim();
    final elapsed = _elapsedLabel();
    final steps = const ['准备', '提交', '识别'];
    final active = _stepIndex;

    const text = Color(0xFF1F242E);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _brand.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '正在生成文稿',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        color: _muted,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0)
                        Expanded(
                          child: Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            color: i <= active
                                ? _brand.withValues(alpha: 0.35)
                                : const Color(0xFFE6E8EC),
                          ),
                        ),
                      Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              i == active ? FontWeight.w600 : FontWeight.w400,
                          color: i <= active
                              ? _brand
                              : _muted.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
                if (hint.isNotEmpty || elapsed.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [
                      if (hint.isNotEmpty) hint,
                      if (elapsed.isNotEmpty) elapsed,
                    ].join('\n'),
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted.withValues(alpha: 0.9),
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 挂在播放器下方：loading / 失败提示；成功态为可点击预览，底部滑出文稿
class TranscriptSegmentPanel extends StatelessWidget {
  const TranscriptSegmentPanel({
    super.key,
    required this.segment,
    this.itemId,
    this.segmentKey,
    this.hidePendingLoading = false,
    this.fontSize = ReadingFontPrefs.defaultSize,
    this.onShareQuote,
  });

  final TranscriptSegment? segment;
  final int? itemId;
  final String? segmentKey;
  /// 思维导图触发的自动转写时，进度已在脑图卡片展示，不重复显示 pending UI
  final bool hidePendingLoading;
  /// 与阅读页正文字号同步（预览与文稿全文）
  final double fontSize;
  final Future<void> Function(String quote, Rect? shareOrigin)? onShareQuote;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _transcriptText = Color(0xFF3A404C);

  void _openTranscriptPage(BuildContext context, TranscriptSegment seg) {
    final text = (seg.text ?? '').trim();
    unawaited(
      showItemTranscriptSheet(
        context,
        text: text,
        cues: seg.cues,
        fontSize: fontSize,
        itemId: itemId,
        segmentKey: segmentKey,
        onShareQuote: onShareQuote,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seg = segment;
    if (seg == null || seg.status == 'none') return const SizedBox.shrink();

    final previewSize = ReadingFontPrefs.clamp(fontSize);

    if (seg.isPending) {
      if (hidePendingLoading) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: TranscriptPendingProgress(segment: seg),
      );
    }

    if (seg.isFailed) {
      final err = (seg.error ?? '').trim();
      if (err.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEEF3FB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _brand.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Text(
            '生成文稿失败：$err',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.4),
          ),
        ),
      );
    }

    if (!seg.hasText) return const SizedBox.shrink();

    final text = seg.text!.trim();
    final charCount = text.replaceAll(RegExp(r'\s'), '').length;
    final metaLabel = charCount > 0 ? '$charCount 字' : '已生成';

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: const Color(0xFFEEF3FB),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openTranscriptPage(context, seg),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _brand.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _brand.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.article_outlined,
                          size: 20,
                          color: _brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '文稿已生成',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _text,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '文稿已就绪 · $metaLabel',
                              style: const TextStyle(
                                fontSize: 13,
                                color: _muted,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _brand,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          '查看全文',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: previewSize,
                        height: 1.55,
                        color: _transcriptText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
