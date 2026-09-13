import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_regenerate_confirm_dialog.dart';
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
  bool _generateInFlight = false;
  int _pollGen = 0;

  AiSummaryMeta get _meta => _item.aiMeta.summary;

  bool get _hasResult => _meta.isSuccess && _meta.hasText;

  bool get _shouldAutoStart =>
      !_meta.isPending && !_meta.isFailed && !_hasResult;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    if (_meta.isPending) {
      unawaited(_poll());
    } else if (_shouldAutoStart) {
      // 首次无内容：直接进 loading 并触发生成
      _requesting = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_generate());
      });
    }
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

  Future<void> _generate({bool force = false}) async {
    if (_generateInFlight || _meta.isPending) return;

    if (_item.hasAnyTranscriptPending && !_meta.awaitTranscript) {
      if (mounted) {
        setState(() => _requesting = false);
        AppToast.show(context, '转写进行中，请稍候再生成 AI 总结');
      }
      return;
    }
    if (!_item.canRequestAiSuggest &&
        !_item.shouldAutoTranscribeBeforeMindmap) {
      if (mounted) {
        setState(() => _requesting = false);
        AppToast.show(context, '内容不足，无法生成 AI 总结');
      }
      return;
    }

    final isRegen = force || _hasResult;
    if (isRegen) {
      final ok = await showReadingRegenerateConfirmDialog(
        context,
        ReadingRegenerateKind.summary,
      );
      if (ok != true || !mounted) return;
      force = true;
    }

    _generateInFlight = true;
    if (!_requesting) setState(() => _requesting = true);
    try {
      Analytics.instance.aiSummaryRequest(
        itemId: widget.itemId,
        force: force,
      );
      final updated = await _repo.requestSummary(
        widget.itemId,
        force: force,
      );
      if (!mounted) return;
      _syncItem(updated);
      _generateInFlight = false;
      setState(() => _requesting = false);
      unawaited(_poll());
    } on ApiException catch (e) {
      if (!mounted) return;
      _generateInFlight = false;
      setState(() => _requesting = false);
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      _generateInFlight = false;
      setState(() => _requesting = false);
      AppToast.show(context, '生成失败，请稍后重试');
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
        if (st.summary.isSuccess) {
          AppToast.show(
            context,
            aiDoneToast('AI 总结已生成', st.summary.creditsUsed),
          );
        } else if (st.summary.isFailed) {
          AppToast.show(context, st.summary.error ?? 'AI 总结生成失败');
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
    final showRegen = _hasResult && !_meta.isPending && !_requesting;

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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'AI 总结',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _text,
                      ),
                    ),
                  ),
                  if (showRegen)
                    GestureDetector(
                      onTap: () => unawaited(_generate(force: true)),
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.refresh_rounded,
                          size: 20,
                          color: _muted,
                        ),
                      ),
                    ),
                  if (showRegen) const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      '关闭',
                      style: TextStyle(fontSize: 14, color: _muted),
                    ),
                  ),
                ],
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

  Widget _buildBody() {
    if (_meta.isPending || _requesting) {
      final label = _meta.awaitTranscript
          ? '转写完成后生成 AI 总结…'
          : 'AI 总结生成中…';
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
              err.isEmpty ? 'AI 总结生成失败' : 'AI 总结失败：$err',
              style: const TextStyle(
                fontSize: 13,
                color: _muted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => unawaited(_generate(force: true)),
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
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: SingleChildScrollView(
          child: Text(
            _meta.text!.trim(),
            style: const TextStyle(
              fontSize: 15,
              color: _text,
              height: 1.65,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        '根据正文提炼核心要点，方便快速回顾',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          color: _muted.withValues(alpha: 0.9),
          height: 1.5,
        ),
      ),
    );
  }
}
