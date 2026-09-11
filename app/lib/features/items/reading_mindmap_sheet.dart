import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/ai_mindmap_panel.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/mindmap_image_export.dart';
import 'package:super_collection/features/items/reading_regenerate_confirm_dialog.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

Future<void> showReadingMindmapSheet(
  BuildContext context, {
  required int itemId,
  required CollectionItem initialItem,
  String? sourceTitle,
  void Function(CollectionItem item)? onItemUpdated,
}) {
  return showAppBottomSheet<void>(
    context: context,
    builder: (context) => _ReadingMindmapSheet(
      itemId: itemId,
      initialItem: initialItem,
      sourceTitle: sourceTitle,
      onItemUpdated: onItemUpdated,
    ),
  );
}

class _ReadingMindmapSheet extends StatefulWidget {
  const _ReadingMindmapSheet({
    required this.itemId,
    required this.initialItem,
    this.sourceTitle,
    this.onItemUpdated,
  });

  final int itemId;
  final CollectionItem initialItem;
  final String? sourceTitle;
  final void Function(CollectionItem item)? onItemUpdated;

  @override
  State<_ReadingMindmapSheet> createState() => _ReadingMindmapSheetState();
}

class _ReadingMindmapSheetState extends State<_ReadingMindmapSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _handle = Color(0xFFE5E8ED);
  static const _surface = Color(0xFFF3F6FA);

  final _repo = ItemsRepository();
  late CollectionItem _item;
  bool _requesting = false;
  bool _generateInFlight = false;
  bool _sharing = false;
  int _pollGen = 0;

  AiMindmapMeta get _meta => _item.aiMeta.mindmap;

  bool get _hasResult => _meta.isSuccess && _meta.hasTree;

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
        AppToast.show(context, '转写进行中，请稍候再生成思维导图');
      }
      return;
    }
    if (!_item.canRequestAiSuggest &&
        !_item.shouldAutoTranscribeBeforeMindmap) {
      if (mounted) {
        setState(() => _requesting = false);
        AppToast.show(context, '内容不足，无法生成思维导图');
      }
      return;
    }

    final isRegen = force || _hasResult;
    if (isRegen) {
      final ok = await showReadingRegenerateConfirmDialog(
        context,
        ReadingRegenerateKind.mindmap,
      );
      if (ok != true || !mounted) return;
      force = true;
    }

    _generateInFlight = true;
    if (!_requesting) setState(() => _requesting = true);
    try {
      Analytics.instance.aiMindmapRequest(
        itemId: widget.itemId,
        force: force,
      );
      final updated = await _repo.requestMindmap(
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
        final st = await _repo.getMindmapStatus(widget.itemId);
        if (!mounted || gen != _pollGen) return;
        if (st.mindmap.isPending) {
          if (st.mindmap.awaitTranscript) {
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
                        mindmap: st.mindmap,
                        summary: item.aiMeta.summary,
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
                  mindmap: st.mindmap,
                  summary: _item.aiMeta.summary,
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
        if (st.mindmap.isSuccess) {
          AppToast.show(
            context,
            aiDoneToast('思维导图已生成', st.mindmap.creditsUsed),
          );
        } else if (st.mindmap.isFailed) {
          AppToast.show(context, st.mindmap.error ?? '思维导图生成失败');
        }
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  Future<void> _share(AiMindmapNode root, {Rect? shareOrigin}) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final screenSize = MediaQuery.sizeOf(context);
      await shareMindmapImage(
        root: root,
        sourceTitle: widget.sourceTitle,
        sharePositionOrigin: shareOrigin,
        screenSize: screenSize,
      );
    } catch (error, stack) {
      debugPrint('mindmap share failed: $error\n$stack');
      if (mounted) {
        AppToast.show(context, '分享失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.78;
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
                      '思维导图',
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
      final label =
          _meta.awaitTranscript ? '转写完成后生成思维导图…' : '思维导图生成中…';
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
              err.isEmpty ? '思维导图生成失败' : '生成失败：$err',
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

    if (_meta.isSuccess && _meta.hasTree) {
      final root = _meta.tree!;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ColoredBox(
              color: _surface,
              child: MindmapInteractiveView(
                root: root,
                collapsed: const {},
                onToggle: (_) {},
                viewHeight: 280,
                onPreviewTap: () => showMindmapFullscreen(
                  context,
                  root: root,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Expanded(
                  child: Text(
                    '点击思维导图进入全屏；全屏内可折叠节点、双指缩放',
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _SheetMindmapShareButton(
                  loading: _sharing,
                  onTap: _sharing
                      ? null
                      : (origin) => _share(root, shareOrigin: origin),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        '把文章结构拆成脑图，方便浏览与分享',
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

class _SheetMindmapShareButton extends StatelessWidget {
  const _SheetMindmapShareButton({
    required this.onTap,
    this.loading = false,
  });

  final void Function(Rect? shareOrigin)? onTap;
  final bool loading;

  static Rect? _shareOriginFor(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap == null ? null : () => onTap!(_shareOriginFor(context)),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _ReadingMindmapSheetState._blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _ReadingMindmapSheetState._blue.withValues(alpha: 0.85),
                ),
              )
            else
              const Icon(
                Icons.ios_share_rounded,
                size: 18,
                color: _ReadingMindmapSheetState._blue,
              ),
            const SizedBox(width: 4),
            const Text(
              '分享',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _ReadingMindmapSheetState._blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
