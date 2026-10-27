import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/ai_scholar_copy.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

Future<void> showReadingSummarySheet(
  BuildContext context, {
  required int itemId,
  required CollectionItem initialItem,
  void Function(CollectionItem item)? onItemUpdated,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (context) => _ReadingSummarySheet(
      itemId: itemId,
      initialItem: initialItem,
      onItemUpdated: onItemUpdated,
    ),
  );
}

class _ReadingSummarySheet extends StatefulWidget {
  const _ReadingSummarySheet({
    required this.itemId,
    required this.initialItem,
    this.onItemUpdated,
  });

  final int itemId;
  final CollectionItem initialItem;
  final void Function(CollectionItem item)? onItemUpdated;

  @override
  State<_ReadingSummarySheet> createState() => _ReadingSummarySheetState();
}

class _ReadingSummarySheetState extends State<_ReadingSummarySheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);
  static const _surface = Color(0xFFF3F6FA);

  final _repo = ItemsRepository();
  late CollectionItem _item;
  bool _requesting = false;
  bool _retryInFlight = false;
  bool _isPro = false;
  int _pollGen = 0;

  AiSummaryMeta get _meta => _item.aiMeta.summary;

  bool get _hasResult => _meta.isSuccess && _meta.hasText;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    unawaited(_loadPro());
    if (_meta.isPending) {
      unawaited(_poll());
    }
  }

  Future<void> _loadPro() async {
    try {
      final usage = await UsageRepository().fetchUsage();
      if (!mounted) return;
      setState(() => _isPro = usage.isPro);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollGen++;
    super.dispose();
  }

  void _syncItem(CollectionItem item) {
    setState(() => _item = item);
    widget.onItemUpdated?.call(item);
  }

  /// 失败重试：走自动解读通道（不计额度），不再提供「重新生成」入口。
  Future<void> _retryAuto() async {
    if (_retryInFlight || _meta.isPending || _hasResult) return;

    _retryInFlight = true;
    setState(() => _requesting = true);
    try {
      final updated = await _repo.requestSummary(
        widget.itemId,
        auto: true,
      );
      if (!mounted) return;
      _syncItem(updated);
      _retryInFlight = false;
      setState(() => _requesting = false);
      unawaited(_poll());
    } on ApiException catch (e) {
      if (!mounted) return;
      _retryInFlight = false;
      setState(() => _requesting = false);
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      _retryInFlight = false;
      setState(() => _requesting = false);
      AppToast.show(context, '生成失败，请稍后重试');
    }
  }

  Future<void> _shareSummary(Rect? origin) async {
    final text = _meta.shareText;
    if (text.isEmpty) return;
    final canonical = _item.canonicalUrl?.trim();
    final link = (canonical != null && canonical.isNotEmpty)
        ? canonical
        : _item.url.trim();
    try {
      await shareReadingQuote(
        context: context,
        quote: text,
        title: (_item.title ?? '').trim(),
        link: link,
        coverUrl: _item.shareCoverUrl,
        pageUrl: _item.sourcePageUrl,
        kind: ReadingShareKind.summary,
        sharePositionOrigin: origin,
        screenSize: MediaQuery.sizeOf(context),
      );
    } catch (error, stack) {
      debugPrint('summary share failed: $error\n$stack');
      if (mounted) AppToast.show(context, '分享失败，请稍后重试');
    }
  }

  Future<void> _poll() async {
    final gen = ++_pollGen;
    final awaitingTranscript = _meta.awaitTranscript;
    final maxAttempts = awaitingTranscript ? 90 : 45;
    final interval = awaitingTranscript
        ? const Duration(seconds: 4)
        : const Duration(seconds: 2);
    String? lastPhaseFingerprint;

    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      if (!mounted || gen != _pollGen) return;
      try {
        final st = await _repo.getSummaryStatus(widget.itemId);
        if (!mounted || gen != _pollGen) return;
        if (st.summary.isPending) {
          if (st.summary.awaitTranscript) {
            final ts = await _repo.getTranscriptStatus(widget.itemId);
            if (!mounted || gen != _pollGen) return;
            final merged = Map<String, TranscriptSegment>.from(
              _item.transcriptSegments,
            );
            ts.segments.forEach((key, seg) {
              merged[key] = seg;
            });
            final fp = ts.segments.entries
                .map((e) => '${e.key}:${e.value.phase}:${e.value.phaseLabel}')
                .join('|');
            if (fp != lastPhaseFingerprint || _meta.status != 'pending') {
              lastPhaseFingerprint = fp;
              final item = await _repo.getItem(widget.itemId);
              if (!mounted || gen != _pollGen) return;
              _syncItem(
                item
                    .withAiMeta(
                      AiMeta(
                        tags: item.aiMeta.tags,
                        mindmap: item.aiMeta.mindmap,
                        summary: st.summary,
                        model: st.model ?? item.aiMeta.model,
                      ),
                    )
                    .withTranscriptSegments(merged),
              );
            }
          } else if (_meta.status != 'pending') {
            _syncItem(
              _item.withAiMeta(
                AiMeta(
                  tags: _item.aiMeta.tags,
                  mindmap: _item.aiMeta.mindmap,
                  summary: st.summary,
                  model: st.model,
                ),
              ),
            );
          }
          continue;
        }

        final item = await _repo.getItem(widget.itemId);
        if (!mounted || gen != _pollGen) return;
        _syncItem(item);
        if (st.summary.isFailed) {
          AppToast.show(context, st.summary.error ?? 'AI 解读生成失败');
        }
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'AI 解读',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxSheetHeight - 108),
                child: _buildBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryBlock(String label, String body, {bool share = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: _muted,
              ),
            ),
            if (share) ...[
              const SizedBox(width: 8),
              _summaryShareButton(),
            ],
          ],
        ),
        const SizedBox(height: 6),
        _bodyText(body),
      ],
    );
  }

  Widget _bodyText(String body) {
    return SelectableText(
      body,
      style: const TextStyle(
        fontSize: 15,
        color: _text,
        height: 1.65,
      ),
    );
  }

  Widget _summaryShareButton() {
    return Builder(
      builder: (buttonContext) => GestureDetector(
        onTap: () {
          final box = buttonContext.findRenderObject() as RenderBox?;
          final origin = box != null && box.hasSize && !box.size.isEmpty
              ? box.localToGlobal(Offset.zero) & box.size
              : null;
          unawaited(_shareSummary(origin));
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ios_share_rounded,
              size: 14,
              color: _blue,
            ),
            SizedBox(width: 2),
            Text(
              '分享',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: _blue,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_meta.isPending || _requesting) {
      final label = _meta.awaitTranscript
          ? '转写完成后生成 AI 解读…'
          : aiScholarGeneratingLabel('解读', isPro: _isPro);
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _blue.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: _muted.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_meta.isFailed) {
      final err = (_meta.error ?? '').trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              err.isEmpty ? 'AI 解读生成失败' : 'AI 解读失败：$err',
              style: const TextStyle(
                fontSize: 13,
                color: _muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => unawaited(_retryAuto()),
              child: const Text(
                '重试',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _blue,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_meta.hasText) {
      final brief = (_meta.brief ?? '').trim();
      final text = _meta.text!.trim();
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (brief.isNotEmpty) ...[
                _summaryBlock('总结', brief, share: true),
                const SizedBox(height: 16),
                _summaryBlock('解读', text),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: _summaryShareButton(),
                ),
                const SizedBox(height: 6),
                _bodyText(text),
              ],
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '解析完成后会自动生成总结与解读',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: _muted.withValues(alpha: 0.9),
              height: 1.5,
            ),
          ),
          if (_item.canRequestAiSuggest &&
              !_item.shouldAutoTranscribeBeforeMindmap) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => unawaited(_retryAuto()),
              child: const Text(
                '现在生成',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _blue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
