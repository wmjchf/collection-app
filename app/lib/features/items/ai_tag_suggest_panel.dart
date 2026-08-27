import 'package:flutter/material.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';

/// 阅读页正文下方：AI 标签建议 loading / 结果 / 失败
class AiTagSuggestPanel extends StatefulWidget {
  const AiTagSuggestPanel({
    super.key,
    required this.tagsMeta,
    this.onApply,
    this.onDismiss,
    this.onRetry,
  });

  final AiTagsMeta tagsMeta;
  final Future<void> Function(List<String> names)? onApply;
  final VoidCallback? onDismiss;
  final VoidCallback? onRetry;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _surface = Color(0xFFF3F6FA);
  static const _chipOn = Color(0xFFE5EDFF);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipNewBorder = Color(0xFFD9DBE0);

  @override
  State<AiTagSuggestPanel> createState() => _AiTagSuggestPanelState();
}

class _AiTagSuggestPanelState extends State<AiTagSuggestPanel> {
  final _selected = <String>{};
  bool _applying = false;

  @override
  void didUpdateWidget(covariant AiTagSuggestPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tagsMeta.generatedAt != widget.tagsMeta.generatedAt) {
      _selected
        ..clear()
        ..addAll(widget.tagsMeta.items.map((e) => e.name));
    }
  }

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.tagsMeta.items.map((e) => e.name));
  }

  Future<void> _apply() async {
    if (_applying || _selected.isEmpty) return;
    setState(() => _applying = true);
    try {
      await widget.onApply?.call(_selected.toList());
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.tagsMeta;
    if (meta.status == 'none' || meta.status == 'skipped') {
      return const SizedBox.shrink();
    }

    if (meta.isPending) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _AiTagLoadingCard(awaitTranscript: meta.awaitTranscript),
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
              Text(
                err.isEmpty ? '标签建议生成失败' : '标签建议失败：$err',
                style: const TextStyle(
                  fontSize: 13,
                  color: AiTagSuggestPanel._muted,
                  height: 1.4,
                ),
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: widget.onRetry,
                  child: const Text(
                    '重试',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AiTagSuggestPanel._brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (meta.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI 建议标签',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AiTagSuggestPanel._text,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '本篇标签已较完整，暂无新的建议',
                style: TextStyle(
                  fontSize: 13,
                  color: AiTagSuggestPanel._muted,
                  height: 1.4,
                ),
              ),
              if (widget.onDismiss != null) ...[
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: const Text(
                    '知道了',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AiTagSuggestPanel._brand,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!meta.hasSuggestions) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _AiCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'AI 建议标签',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AiTagSuggestPanel._text,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in meta.items)
                  GestureDetector(
                    onTap: _applying
                        ? null
                        : () => setState(() {
                              if (_selected.contains(item.name)) {
                                _selected.remove(item.name);
                              } else {
                                _selected.add(item.name);
                              }
                            }),
                    child: _SuggestChip(
                      label: item.name,
                      isExisting: item.existingTagId != null,
                      selected: _selected.contains(item.name),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: _applying || _selected.isEmpty ? null : _apply,
                  child: Text(
                    _applying ? '采纳中…' : '采纳所选',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _selected.isEmpty || _applying
                          ? AiTagSuggestPanel._muted
                          : AiTagSuggestPanel._brand,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: _applying ? null : widget.onDismiss,
                  child: Text(
                    '忽略',
                    style: TextStyle(
                      fontSize: 14,
                      color: AiTagSuggestPanel._muted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '带 ＋ 为新建建议，其余为已有标签（可复用）',
              style: TextStyle(
                fontSize: 12,
                color: AiTagSuggestPanel._muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestChip extends StatelessWidget {
  const _SuggestChip({
    required this.label,
    required this.isExisting,
    required this.selected,
  });

  final String label;
  final bool isExisting;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final bg = selected
        ? AiTagSuggestPanel._chipOn
        : (isExisting ? AiTagSuggestPanel._chipBg : Colors.white);
    final fg = selected
        ? AiTagSuggestPanel._brand
        : AiTagSuggestPanel._text;
    final borderColor = selected
        ? AiTagSuggestPanel._chipOn
        : (isExisting
            ? AiTagSuggestPanel._chipBg
            : AiTagSuggestPanel._chipNewBorder);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (!isExisting)
              TextSpan(
                text: '＋ ',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AiTagSuggestPanel._muted,
                ),
              ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiTagLoadingCard extends StatelessWidget {
  const _AiTagLoadingCard({this.awaitTranscript = false});

  final bool awaitTranscript;

  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _surface = Color(0xFFF3F6FA);

  @override
  Widget build(BuildContext context) {
    final title = awaitTranscript
        ? '正在转写，完成后生成标签建议…'
        : '正在生成标签建议…';
    final subtitle = awaitTranscript
        ? '转写完成后将自动开始生成'
        : '完成后可选择采纳，不会自动修改标签';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(8),
      ),
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
            subtitle,
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
}

class _AiCard extends StatelessWidget {
  const _AiCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AiTagSuggestPanel._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}
