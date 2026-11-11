import 'dart:async';
import 'dart:ui' show BoxHeightStyle, BoxWidthStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/analytics/screen_dwell_tracker.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/network/media_http_headers.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/core/ui/app_side_drawer.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/core/ui/parse_progress_tracker.dart';
import 'package:super_collection/core/ui/pro_copy.dart';
import 'package:super_collection/features/agent/agent_host.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/home/roam_models.dart';
import 'package:super_collection/features/home/widgets/roam_quote_card.dart';
import 'package:super_collection/features/items/ai_meta_models.dart';
import 'package:super_collection/features/items/article_body_text.dart';
import 'package:super_collection/features/items/article_content_blocks.dart';
import 'package:super_collection/features/items/article_markdown.dart';
import 'package:super_collection/features/items/item_image_gallery.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_video_player.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_media_controller.dart';
import 'package:super_collection/features/items/reading_annotation_sheet.dart';
import 'package:super_collection/features/items/reading_delete_confirm_dialog.dart';
import 'package:super_collection/features/items/reading_font_prefs.dart';
import 'package:super_collection/features/items/reading_font_size_sheet.dart';
import 'package:super_collection/features/items/reading_more_sheet.dart';
import 'package:super_collection/features/items/reading_content_edit_page.dart';
import 'package:super_collection/features/items/reading_mindmap_sheet.dart';
import 'package:super_collection/features/items/reading_note_sheet.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';
import 'package:super_collection/features/items/reading_reparse_confirm_dialog.dart';
import 'package:super_collection/features/items/reading_title_edit_dialog.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';
import 'package:super_collection/features/items/reading_tags_sheet.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/items/item_transcript_page.dart';
import 'package:super_collection/features/items/item_transcript_refresh.dart';

/// 本地阅读页：标题 + 可读正文（含标注高亮）；底栏 助手 / 标签 / 感想 / 更多（思维导图）。
/// 单篇解读 / 转写改走助手；不再单独挂 AI 解读与「更多」转写入口。
class ItemReadingPage extends StatefulWidget {
  const ItemReadingPage({
    super.key,
    required this.itemId,
    this.initialItem,
    this.openEntry = 'unknown',
    this.focusAnnotationId,
    this.openNoteOnLaunch = false,
    this.embedded = false,
    this.onDeleted,
  });

  final int itemId;
  final CollectionItem? initialItem;

  /// 打开来源：home / unread / library / search / star / tag / paste / roam / unknown
  final String openEntry;

  /// 打开后滚动到该标注/批注在正文中的位置（如漫游进入）
  final int? focusAnnotationId;

  /// 打开后直接弹出感想（如漫游点感想进入）
  final bool openNoteOnLaunch;

  /// iPad 分栏嵌入：无返回钮，删除后回调宿主而非 pop。
  final bool embedded;

  final VoidCallback? onDeleted;

  @override
  State<ItemReadingPage> createState() => _ItemReadingPageState();
}

class _ItemReadingPageState extends State<ItemReadingPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _border = Color(0xFFE5E5EB);
  static const _blue = Color(0xFF2F6FED);
  /// 图集正文 / 标签行：略淡于品牌蓝
  static const _tagSoftBlue = Color(0xFF6B9AE8);
  static const _highlight = Color(0xFFFFF2C7);

  static const _chromeAnim = Duration(milliseconds: 240);
  static const _topBarHeight = 52.0;
  static const _bottomBarHeight = 56.0;
  static const _bottomBarHInset = 16.0;
  static const _bottomBarGap = 10.0;
  static const _bottomBarRadius = 28.0;
  static const _bottomBarAgentGap = 10.0;

  final _repo = ItemsRepository();
  final _tagsRepo = TagsRepository();
  final _usageRepo = UsageRepository();
  final _scrollController = ScrollController();
  late CollectionItem _item;
  List<Tag> _itemTags = const [];
  List<ItemAnnotation> _annotations = const [];
  bool _loadingAnns = true;
  bool _chromeVisible = true;
  late final ReadingMediaController _pageAudio = ReadingMediaController();
  Timer? _itemPollTimer;
  Timer? _markReadTimer;
  bool _pageLoading = false;
  String? _pageError;
  bool _markedRead = false;
  bool _handlingBack = false;
  bool _tagLeaveNudgeDone = false;
  bool _isPro = false;
  int _summaryPollGen = 0;
  int _mindmapPollGen = 0;
  int _transcriptPollGen = 0;
  late final DateTime _openedAt;
  double _bodyFontSize = ReadingFontPrefs.defaultSize;
  bool _focusScrollDone = false;

  /// 侧栏点选后滚动定位到正文高亮（与入页 focusAnnotationId 分开）
  int? _locateAnnotationId;
  bool _noteSheetLaunched = false;

  /// 停留满此时长才标已读，避免误点进阅读页就从「未读」消失。
  static const _markReadDelay = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _openedAt = DateTime.now();
    ItemTranscriptRefresh.version.addListener(_onExternalTranscriptRefresh);
    unawaited(_loadPro());
    unawaited(_loadBodyFontSize());
    final initial = widget.initialItem;
    _item = initial ??
        CollectionItem(
          id: widget.itemId,
          url: '',
          status: 'pending',
        );
    Analytics.instance.itemOpen(
      itemId: widget.itemId,
      entry: widget.openEntry,
      platform: initial?.platform,
    );
    _pageLoading = initial == null;
    if (initial != null) {
      _syncItemPolling(initial);
      if (initial.isSuccess) {
        _scheduleMarkReadIfNeeded();
        _onItemReadyForReading(initial);
      }
      _scheduleOpenNoteOnLaunch();
    }
    unawaited(_bootstrapItem());
  }

  void _scheduleOpenNoteOnLaunch() {
    if (!widget.openNoteOnLaunch || _noteSheetLaunched) return;
    _noteSheetLaunched = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_onNote());
    });
  }

  Future<void> _loadPro() async {
    try {
      final usage = await _usageRepo.fetchUsage();
      if (!mounted) return;
      setState(() => _isPro = usage.isPro);
    } catch (_) {}
  }

  Future<void> _loadBodyFontSize() async {
    final size = await ReadingFontPrefs.load();
    if (!mounted) return;
    if (size == _bodyFontSize) return;
    setState(() => _bodyFontSize = size);
  }

  TextStyle get _bodyTextStyle => TextStyle(
        fontSize: _bodyFontSize,
        height: 1.85,
        letterSpacing: 0.2,
        color: _text,
      );

  /// 图集说明：行高略收；颜色与文章正文同为黑色
  TextStyle get _galleryCaptionStyle => TextStyle(
        fontSize: _bodyFontSize,
        height: 1.65,
        letterSpacing: 0.15,
        color: _text,
      );

  void _onBodyFontSizeChanged(double size) {
    final next = ReadingFontPrefs.clamp(size);
    if (next == _bodyFontSize) return;
    setState(() => _bodyFontSize = next);
    unawaited(ReadingFontPrefs.save(next));
  }

  Future<void> _openAgent() => openAgent(
        context,
        focusItemId: _item.id,
        focusItem: _item,
      );

  void _onExternalTranscriptRefresh() {
    final id = ItemTranscriptRefresh.lastItemId;
    if (id == null || id != widget.itemId) return;
    unawaited(_refreshItemAfterExternalTranscript());
  }

  /// 助手等处转写成功后刷新本页文稿展示。
  Future<void> _refreshItemAfterExternalTranscript() async {
    try {
      final item = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      setState(() => _item = item);
      _ensureBackgroundPolling(item);
    } catch (_) {
      // 刷新失败不打断阅读
    }
  }

  Future<void> _openFontSizeSheet() {
    return showReadingFontSizeSheet(
      context,
      fontSize: _bodyFontSize,
      onChanged: _onBodyFontSizeChanged,
    );
  }

  /// 视频类顶栏「文稿」：有成功文稿则打开；否则提示去助手转写。
  bool get _showTranscriptHeaderEntry => _item.hasVideo;

  Future<void> _openTranscriptFromHeader() async {
    var key = TranscriptTargets.segmentVideoUrl;
    var seg = _item.segmentTranscript(key);
    if (seg == null || !seg.hasText) {
      for (final e in _item.transcriptSegments.entries) {
        if (e.value.isSuccess && e.value.hasText) {
          key = e.key;
          seg = e.value;
          break;
        }
      }
    }
    if (seg == null || !seg.hasText) {
      if (!mounted) return;
      AppToast.show(context, '暂无文稿，可在助手里转写');
      return;
    }
    await showItemTranscriptSheet(
      context,
      text: seg.text!.trim(),
      cues: seg.cues,
      fontSize: _bodyFontSize,
      itemId: _item.id,
      segmentKey: key,
      onShareQuote: _shareExistingQuote,
    );
  }

  @override
  void dispose() {
    final seconds = DateTime.now().difference(_openedAt).inSeconds;
    if (seconds >= 1) {
      Analytics.instance.readingDwell(
        itemId: widget.itemId,
        seconds: seconds,
      );
      Analytics.instance.screenDwell(
        screen: AnalyticsScreens.reading,
        seconds: seconds,
        props: {'item_id': widget.itemId},
      );
    }
    unawaited(Analytics.instance.flush());
    ItemTranscriptRefresh.version.removeListener(_onExternalTranscriptRefresh);
    _markReadTimer?.cancel();
    _itemPollTimer?.cancel();
    _summaryPollGen++;
    _mindmapPollGen++;
    _scrollController.dispose();
    _pageAudio.dispose();
    super.dispose();
  }

  Future<void> _bootstrapItem() async {
    try {
      final item = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      final wasSuccess = _item.isSuccess;
      setState(() {
        _item = item;
        _pageLoading = false;
        _pageError = null;
      });
      _syncItemPolling(item);
      if (item.isSuccess) {
        if (!wasSuccess) {
          _scheduleMarkReadIfNeeded();
          _onItemReadyForReading(item);
        } else {
          // 重进已成功条目：列表可能仍是旧 segments，补拉转写/AI 进度
          _ensureBackgroundPolling(item);
        }
      }
      _scheduleOpenNoteOnLaunch();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pageLoading = false;
        _pageError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pageLoading = false;
        _pageError = '加载失败';
      });
    }
  }

  void _syncItemPolling(CollectionItem item) {
    _itemPollTimer?.cancel();
    if (!item.isPending) return;
    _itemPollTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
      _pollItemOnce();
    });
  }

  Future<void> _pollItemOnce() async {
    try {
      final item = await _repo.getItem(widget.itemId);
      if (!mounted) return;
      final wasSuccess = _item.isSuccess;
      setState(() => _item = item);
      if (!item.isPending) {
        _itemPollTimer?.cancel();
      }
      if (item.isSuccess && !wasSuccess) {
        _scheduleMarkReadIfNeeded();
        _onItemReadyForReading(item);
      }
    } catch (_) {
      // 轮询失败不打断页面
    }
  }

  void _onItemReadyForReading(CollectionItem item) {
    _loadAnnotations();
    unawaited(_loadItemTags());
    unawaited(ReadingMediaController.ensureAudioSession());
    _ensureBackgroundPolling(item);
    _precacheShareCover(item);
  }

  /// 转写 / AI 进行中时拉起轮询（重进阅读页也要补上，否则步骤条停在旧态或不刷新）
  void _ensureBackgroundPolling(CollectionItem item) {
    if (item.hasAnyTranscriptPending && !item.isAiAwaitingTranscript) {
      _pollTranscript();
    }
    if (item.hasAiTagsPending) {
      unawaited(_pollAiSuggestInBackground());
    }
    if (item.hasMindmapPending) {
      _pollMindmap();
    }
    if (item.hasSummaryPending) {
      _pollSummary();
    }
  }

  void _precacheShareCover(CollectionItem item) {
    final raw = item.shareCoverUrl?.trim() ?? '';
    if (raw.isEmpty) return;
    final resolved = resolveMediaUrl(raw);
    final uri = Uri.tryParse(resolved);
    if (uri == null || !uri.hasScheme) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        precacheImage(
          NetworkImage(
            resolved,
            headers: mediaHttpHeadersFor(
              resolved,
              pageUrl: item.sourcePageUrl,
            ),
          ),
          context,
        ).catchError((Object _) {}),
      );
    });
  }

  void _scheduleMarkReadIfNeeded() {
    if (_markedRead || !_item.isSuccess || !_item.isUnread) return;
    _markReadTimer?.cancel();
    _markReadTimer = Timer(_markReadDelay, () {
      unawaited(_markReadIfNeeded());
    });
  }

  Future<void> _markReadIfNeeded() async {
    _markReadTimer = null;
    if (_markedRead || !_item.isSuccess || !_item.isUnread) return;
    _markedRead = true;
    try {
      final item = await _repo.markAsRead(widget.itemId);
      if (!mounted) return;
      setState(() => _item = item);
    } catch (_) {
      _markedRead = false;
    }
  }

  Future<void> _markAsUnread() async {
    _markReadTimer?.cancel();
    _markReadTimer = null;
    // 本页停留期间不再自动标已读；下次进入会重新计时。
    _markedRead = true;
    try {
      final item = await _repo.markAsUnread(widget.itemId);
      if (!mounted) return;
      setState(() => _item = item);
      AppToast.show(context, markedAsUnreadToast(isPro: _isPro));
    } on ApiException catch (e) {
      if (!mounted) return;
      _markedRead = false;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      _markedRead = false;
      AppToast.show(context, '操作失败');
    }
  }

  /// 离开时是否要先问「还没有标签」。为 true 时系统右滑会被关掉，改由左缘手势触发返回。
  bool get _shouldNudgeOnLeave {
    final engaged = _markedRead ||
        DateTime.now().difference(_openedAt) >= _markReadDelay;
    return _item.isSuccess &&
        _itemTags.isEmpty &&
        !_tagLeaveNudgeDone &&
        engaged;
  }

  /// 离开阅读页：若已认真看过且仍无标签，轻推打标（可跳过）。
  /// 需要拦截时 [PopScope.canPop] 为 false，须用 [Navigator.pop] 强制出栈。
  Future<void> _handleBack() async {
    if (widget.embedded) return;
    if (_handlingBack) return;
    _handlingBack = true;
    try {
      if (_shouldNudgeOnLeave) {
        _tagLeaveNudgeDone = true;
        final goTag = await showAppConfirmDialog(
          context,
          title: '还没有标签',
          message: '给这篇加个标签，之后更好找。',
          cancelLabel: '暂不',
          confirmLabel: '去打标',
          dangerConfirm: false,
        );
        if (!mounted) return;
        if (goTag == true) {
          await _openTagsSheet();
          if (!mounted) return;
        }
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      _handlingBack = false;
    }
  }

  Future<void> _reparseItem() async {
    if (_item.hasUserEditedContent) {
      final ok = await showReadingReparseConfirmDialog(
        context,
        hasUserEditedContent: true,
      );
      if (ok != true || !mounted) return;
    }
    try {
      ParseProgressTracker.begin();
      final item = await _repo.reparse(
        widget.itemId,
        forceOverwrite: _item.hasUserEditedContent,
      );
      if (!mounted) return;
      setState(() => _item = item);
      _syncItemPolling(item);
      // ignore: unawaited_futures
      ParseProgressTracker.watchItem(
        item.id,
        initialStatus: item.status,
        platform: item.platform,
        url: item.canonicalUrl ?? item.url,
        onSettled: () async {
          if (!mounted) return;
          try {
            final refreshed = await _repo.getItem(widget.itemId);
            if (!mounted) return;
            final wasSuccess = _item.isSuccess;
            setState(() => _item = refreshed);
            _syncItemPolling(refreshed);
            if (refreshed.isSuccess && !wasSuccess) {
              _scheduleMarkReadIfNeeded();
              _onItemReadyForReading(refreshed);
            }
          } catch (_) {}
        },
      );
    } on ApiException catch (e) {
      ParseProgressTracker.cancel();
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  String get _linkToCopy {
    final canonical = _item.canonicalUrl?.trim();
    if (canonical != null && canonical.isNotEmpty) return canonical;
    return _item.url.trim();
  }

  Future<void> _copyLink() async {
    final link = _linkToCopy;
    if (link.isEmpty) {
      AppToast.show(context, '暂无链接');
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    AppToast.show(context, '链接已复制');
  }

  Future<void> _confirmDelete() async {
    final ok = await showReadingDeleteConfirmDialog(context);
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteItem(_item.id);
      if (!mounted) return;
      AppToast.show(context, '已删除');
      if (widget.embedded) {
        widget.onDeleted?.call();
      } else {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    }
  }

  Future<void> _loadItemTags() async {
    try {
      final tags = await _repo.listItemTags(_item.id);
      if (!mounted) return;
      setState(() {
        _itemTags = tags.where((t) => !t.isSystem).toList(growable: false);
      });
    } catch (_) {
      // ignore
    }
  }

  String get _rawBody => (_item.content ?? _item.summary ?? '').trim();

  /// 标注 / 选区用的可见纯文字（去掉图标记与 ** / # 等）
  String get _bodyText {
    final plain = ArticleMarkdown.visiblePlain(_rawBody);
    return ArticleBodyText.splitParagraphs(plain).join('\n\n');
  }

  List<ArticleBlock> get _bodyBlocks => ArticleContentBlocks.parse(_rawBody);

  /// 图集阅读轮播用图（仅 `isImageGallery`）
  List<String> get _readingImageUrls {
    if (!_item.isImageGallery) return const [];
    return _item.imageUrls
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  bool get _hasInlineVideos =>
      ArticleContentBlocks.hasInlineVideos(_rawBody);

  /// 顶栏真视频（非播客、非文中内嵌）：媒体优先版式
  bool get _isTopBarTrueVideo {
    if (!_item.hasVideo || _hasInlineVideos) return false;
    final url = _item.videoUrl?.trim() ?? '';
    if (url.isEmpty) return false;
    return !isAudioOnlyMediaUrl(url, platform: _item.platform);
  }

  bool get _platformNeedsVideoRefresh {
    final p = (_item.platform ?? '').toLowerCase();
    final v = (_item.videoUrl ?? '').toLowerCase();
    final body = (_item.content ?? '').toLowerCase();
    return p == 'bilibili' ||
        p == 'toutiao' ||
        p == 'qqnews' ||
        p == 'sina' ||
        v.contains('bilivideo') ||
        v.contains('bilibili') ||
        v.contains('toutiaovod') ||
        v.contains('gtimg.com') ||
        v.contains('weibocdn') ||
        body.contains('gtimg.com') ||
        body.contains('weibocdn');
  }

  Future<String?> _refreshVideoUrl() async {
    final updated = await _repo.refreshVideo(_item.id);
    // 不 setState：避免 url 变化触发播放器重建死循环；由播放器内部换链
    _item = updated;
    return updated.videoUrl;
  }

  Future<String?> _refreshInlineVideo(int index) async {
    final updated = await _repo.refreshVideo(_item.id);
    if (!mounted) return null;
    setState(() => _item = updated);
    final urls = ArticleContentBlocks.inlineVideoUrls(_rawBody);
    if (index >= 0 && index < urls.length) return urls[index];
    return updated.videoUrl;
  }

  String _metaLine() {
    final date = _item.createdAt?.toLocal();
    final dateStr = date == null
        ? ''
        : '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
    return [
      platformLabel(
        _item.platform,
        url: (_item.canonicalUrl?.trim().isNotEmpty == true)
            ? _item.canonicalUrl
            : _item.url,
      ),
      dateStr,
    ].where((e) => e.isNotEmpty).join(' · ');
  }

  List<Widget> _buildBodyContent(
    String body, {
    required bool gallery,
  }) {
    if (_rawBody.isEmpty) {
      if (gallery) return const [];
      return const [
        Text(
          '暂无正文',
          style: TextStyle(fontSize: 15, color: _muted),
        ),
      ];
    }
    if (!gallery && ArticleContentBlocks.hasRichMarkup(_rawBody)) {
      return [
        _InlineArticleBody(
          blocks: _bodyBlocks,
          plainText: body,
          fontSize: _bodyFontSize,
          annotationRanges: _annotationRanges(body),
          toolbarAt: _toolbarAt,
          onTapAnnotation: _openAnnotation,
          focusAnnotationId:
              _locateAnnotationId ?? widget.focusAnnotationId,
          onFocusAnnotationRect: _onFocusAnnotationRect,
          itemId: _item.id,
          pageUrl: _item.sourcePageUrl,
          platform: _item.platform,
          pageAudio: _pageAudio,
          onRefreshInlineVideo:
              _platformNeedsVideoRefresh ? _refreshInlineVideo : null,
        ),
      ];
    }
    // 图集正文原样展示（含 #标签，不做高亮/剔除）
    return [
      _AnnotatedBodyStack(
        text: body,
        spans: _bodySpans(body),
        annotations: _annotationRanges(body),
        contextMenuBuilder: _selectionToolbar,
        onTapAnnotation: _openAnnotation,
        textStyle: gallery ? _galleryCaptionStyle : _bodyTextStyle,
        focusAnnotationId:
            _locateAnnotationId ?? widget.focusAnnotationId,
        onFocusAnnotationRect: _onFocusAnnotationRect,
      ),
    ];
  }

  List<Widget> _buildGalleryReadingChildren({
    required String title,
    required String body,
  }) {
    final screenW = MediaQuery.sizeOf(context).width;
    final galleryH = (screenW * 1.05).clamp(300.0, 560.0);
    return [
      ItemImageGallery(
        urls: _readingImageUrls,
        pageUrl: _item.sourcePageUrl,
        height: galleryH,
        borderRadius: 0,
        overlayIndicators: true,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _text,
                height: 1.35,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _metaLine(),
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                height: 1.4,
              ),
            ),
            if (_itemTags.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ArticleTagHashtags(
                tags: _itemTags,
                onTap: _openTagList,
                color: _tagSoftBlue,
              ),
            ],
            if (_rawBody.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._buildBodyContent(body, gallery: true),
            ],
            if (_loadingAnns) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildTopBarVideoReadingChildren({
    required String title,
    required String body,
  }) {
    final screenW = MediaQuery.sizeOf(context).width;
    final playerH = (screenW * 9 / 16).clamp(180.0, 420.0);
    return [
      ItemVideoPlayer(
        key: ValueKey('item-video-${_item.id}'),
        url: _item.videoUrl!.trim(),
        coverUrl: _item.coverImageUrl ??
            (_item.displayImages.isNotEmpty
                ? _item.displayImages.first
                : null),
        pageUrl: _item.sourcePageUrl,
        platform: _item.platform,
        pageAudio: _pageAudio,
        height: playerH,
        borderRadius: 0,
        onRefreshUrl:
            _platformNeedsVideoRefresh ? _refreshVideoUrl : null,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: _text,
                height: 1.35,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _metaLine(),
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                height: 1.4,
              ),
            ),
            if (_itemTags.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ArticleTagHashtags(
                tags: _itemTags,
                onTap: _openTagList,
                color: _tagSoftBlue,
              ),
            ],
            if (_rawBody.isNotEmpty) ...[
              const SizedBox(height: 14),
              ..._buildBodyContent(
                body,
                gallery: false,
              ),
            ],
            if (_loadingAnns) ...[
              const SizedBox(height: 16),
              const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Future<void> _loadAnnotations() async {
    setState(() => _loadingAnns = true);
    try {
      final list = await _repo.listAnnotations(_item.id);
      if (!mounted) return;
      setState(() {
        _annotations = list;
        _loadingAnns = false;
      });
      _scheduleFocusScrollFallback();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAnns = false);
    }
  }

  void _onFocusAnnotationRect(Rect localRect, RenderBox stackBox) {
    if (!mounted) return;
    final locating = _locateAnnotationId != null;
    if (!locating && _focusScrollDone) return;
    if (!_scrollController.hasClients) return;

    if (locating) {
      _locateAnnotationId = null;
    } else {
      _focusScrollDone = true;
    }

    final scrollCtx =
        _scrollController.position.context.notificationContext;
    final scrollBox = scrollCtx?.findRenderObject() as RenderBox?;
    if (scrollBox == null || !scrollBox.hasSize) return;

    final global = stackBox.localToGlobal(localRect.topLeft);
    final viewportTop = scrollBox.localToGlobal(Offset.zero).dy;
    const align = 0.22;
    final desired = scrollBox.size.height * align;
    final delta = (global.dy - viewportTop) - desired;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    if (locating) {
      unawaited(
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        ),
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  void _locateAnnotation(ItemAnnotation ann) {
    final segmentKey = ann.transcriptSegmentKey;
    if (segmentKey != null) {
      final seg = _item.segmentTranscript(segmentKey);
      final text = (seg?.text ?? '').trim();
      if (text.isNotEmpty) {
        unawaited(
          showItemTranscriptSheet(
            context,
            text: text,
            cues: seg?.cues ?? const [],
            fontSize: _bodyFontSize,
            itemId: _item.id,
            segmentKey: segmentKey,
            focusAnnotationId: ann.id,
            onShareQuote: _shareExistingQuote,
          ),
        );
        return;
      }
    }

    setState(() => _locateAnnotationId = ann.id);
    // 量不到热区时退回 TextPainter 估算
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        if (!mounted || _locateAnnotationId != ann.id) return;
        _scrollToBodyAnnotationByPainter(ann.id);
        if (mounted) setState(() => _locateAnnotationId = null);
      });
    });
  }

  void _scrollToBodyAnnotationByPainter(int annotationId) {
    if (!_scrollController.hasClients) return;
    final body = _bodyText;
    if (body.isEmpty) return;
    ({int start, int end, ItemAnnotation ann})? target;
    for (final r in _annotationRanges(body)) {
      if (r.ann.id == annotationId) {
        target = r;
        break;
      }
    }
    if (target == null) return;

    final width = MediaQuery.sizeOf(context).width - 44;
    final painter = TextPainter(
      text: TextSpan(
        text: body.substring(0, target.start),
        style: _bodyTextStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    const aboveBody = 160.0;
    final targetOffset = (aboveBody + painter.height - 80)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    unawaited(
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// 量不到热区时（如表情 WidgetSpan）用 TextPainter 估算滚动
  void _scheduleFocusScrollFallback() {
    final id = widget.focusAnnotationId;
    if (id == null || _focusScrollDone) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 480), () {
        if (!mounted || _focusScrollDone) return;
        _focusScrollByPainter(id);
      });
    });
  }

  void _focusScrollByPainter(int annotationId) {
    if (_focusScrollDone || !_scrollController.hasClients) return;
    final body = _bodyText;
    if (body.isEmpty) return;
    ({int start, int end, ItemAnnotation ann})? target;
    for (final r in _annotationRanges(body)) {
      if (r.ann.id == annotationId) {
        target = r;
        break;
      }
    }
    if (target == null) return;

    final width = MediaQuery.sizeOf(context).width - 44;
    final painter = TextPainter(
      text: TextSpan(
        text: body.substring(0, target.start),
        style: _bodyTextStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);

    // 标题/元信息等上方内容的粗估；有图/视频时可能偏一点，优于完全不滚
    const aboveBody = 160.0;
    final targetOffset = (aboveBody + painter.height - 80)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _focusScrollDone = true;
    _scrollController.jumpTo(targetOffset);
  }

  Future<void> _pollSummary() async {
    final gen = ++_summaryPollGen;
    final awaitingTranscript = _item.aiMeta.summary.awaitTranscript;
    final maxAttempts = awaitingTranscript ? 90 : 45;
    final interval = awaitingTranscript
        ? const Duration(seconds: 4)
        : const Duration(seconds: 2);
    String? lastPhaseFingerprint;
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      if (!mounted || gen != _summaryPollGen) return;
      try {
        final st = await _repo.getSummaryStatus(_item.id);
        if (!mounted || gen != _summaryPollGen) return;
        if (st.summary.isPending) {
          if (st.summary.awaitTranscript) {
            final ts = await _repo.getTranscriptStatus(_item.id);
            if (!mounted || gen != _summaryPollGen) return;
            final merged = Map<String, TranscriptSegment>.from(
              _item.transcriptSegments,
            );
            ts.segments.forEach((key, seg) {
              merged[key] = seg;
            });
            final fp = ts.segments.entries
                .map((e) => '${e.key}:${e.value.phase}:${e.value.phaseLabel}')
                .join('|');
            if (fp != lastPhaseFingerprint ||
                _item.aiMeta.summary.status != 'pending') {
              lastPhaseFingerprint = fp;
              final item = await _repo.getItem(_item.id);
              if (!mounted || gen != _summaryPollGen) return;
              setState(
                () => _item = item
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
          } else if (_item.aiMeta.summary.status != 'pending') {
            setState(
              () => _item = _item.withAiMeta(
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
        final item = await _repo.getItem(_item.id);
        if (!mounted || gen != _summaryPollGen) return;
        setState(() => _item = item);
        if (st.summary.isSuccess) {
          AppToast.show(
            context,
            aiDoneToast('AI 解读已生成', st.summary.creditsUsed),
          );
        } else if (st.summary.isFailed) {
          AppToast.show(context, st.summary.error ?? 'AI 解读生成失败');
        }
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  void _clearToolbar(EditableTextState state) {
    ContextMenuController.removeAny();
    state.hideToolbar();
    final value = state.textEditingValue;
    final end = value.selection.isValid ? value.selection.end : 0;
    state.userUpdateTextEditingValue(
      value.copyWith(selection: TextSelection.collapsed(offset: end)),
      SelectionChangedCause.toolbar,
    );
  }

  /// 本地临时 id：先画出高亮再清选区，避免「选区黄 → 空白 → 高亮黄」闪一下。
  static int _optimisticAnnId = -1;

  Future<ItemAnnotation?> _createHighlight(
    String text,
    int start,
    int end, {
    String? note,
    int? replaceOptimisticId,
  }) async {
    final selected = text.trim();
    if (selected.isEmpty) return null;
    try {
      final ann = await _repo.createAnnotation(
        _item.id,
        selectedText: selected,
        startOffset: start,
        endOffset: end,
        note: note,
      );
      if (!mounted) return null;
      setState(() {
        if (replaceOptimisticId != null) {
          _annotations = [
            for (final a in _annotations)
              if (a.id == replaceOptimisticId) ann else a,
          ];
        } else {
          _annotations = [..._annotations, ann];
        }
      });
      return ann;
    } on ApiException catch (e) {
      if (!mounted) return null;
      if (replaceOptimisticId != null) {
        setState(() {
          _annotations = [
            for (final a in _annotations)
              if (a.id != replaceOptimisticId) a,
          ];
        });
      }
      AppToast.show(context, e.message);
      return null;
    }
  }

  Future<void> _onHighlight(
    EditableTextState state,
    String text,
    int start,
    int end,
  ) async {
    final selected = text.trim();
    if (selected.isEmpty) {
      _clearToolbar(state);
      return;
    }
    final optimisticId = _optimisticAnnId--;
    final optimistic = ItemAnnotation(
      id: optimisticId,
      itemId: _item.id,
      selectedText: selected,
      startOffset: start,
      endOffset: end,
    );
    // 先落背景高亮，再收起选区，视觉上连续。
    setState(() => _annotations = [..._annotations, optimistic]);
    _clearToolbar(state);
    final ann = await _createHighlight(
      text,
      start,
      end,
      replaceOptimisticId: optimisticId,
    );
    if (ann != null && mounted) {
      AppToast.show(context, '已高亮');
    }
  }

  Future<void> _onAddNote(
    EditableTextState state,
    String text,
    int start,
    int end,
  ) async {
    _clearToolbar(state);
    final ann = await showCreateAnnotationNoteSheet(
      context,
      itemId: _item.id,
      selectedText: text,
      startOffset: start,
      endOffset: end,
      isPro: _isPro,
    );
    if (ann != null && mounted) {
      setState(() => _annotations = [..._annotations, ann]);
      AppToast.show(
        context,
        annotationSavedToast(isPro: _isPro),
        actionLabel: '查看',
        onAction: _showNoteAnnotationList,
      );
    }
  }

  Future<void> _onCopy(
    EditableTextState state,
    String text,
  ) async {
    await Clipboard.setData(ClipboardData(text: text));
    _clearToolbar(state);
    if (!mounted) return;
    AppToast.show(context, '已复制');
  }

  Future<void> _onShareQuote(
    EditableTextState state,
    String text, {
    Rect? shareOrigin,
  }) async {
    _clearToolbar(state);
    if (!mounted) return;
    try {
      await shareReadingQuote(
        context: context,
        quote: text,
        title: (_item.title ?? '').trim(),
        link: _linkToCopy,
        coverUrl: _item.shareCoverUrl,
        pageUrl: _item.sourcePageUrl,
        sharePositionOrigin: shareOrigin,
        screenSize: MediaQuery.sizeOf(context),
      );
    } catch (error, stack) {
      debugPrint('quote share failed: $error\n$stack');
      if (mounted) AppToast.show(context, '分享失败，请稍后重试');
    }
  }

  Future<void> _shareExistingQuote(
    String quote,
    Rect? shareOrigin, {
    String? note,
  }) async {
    try {
      await shareReadingQuote(
        context: context,
        quote: quote,
        note: note,
        title: (_item.title ?? '').trim(),
        link: _linkToCopy,
        coverUrl: _item.shareCoverUrl,
        pageUrl: _item.sourcePageUrl,
        sharePositionOrigin: shareOrigin,
        screenSize: MediaQuery.sizeOf(context),
      );
    } catch (error, stack) {
      debugPrint('quote share failed: $error\n$stack');
      if (mounted) AppToast.show(context, '分享失败，请稍后重试');
    }
  }

  void _openAnnotation(ItemAnnotation ann) {
    final segmentKey = ann.transcriptSegmentKey;
    if (segmentKey != null) {
      final seg = _item.segmentTranscript(segmentKey);
      final text = (seg?.text ?? '').trim();
      if (text.isNotEmpty) {
        unawaited(
          showItemTranscriptSheet(
            context,
            text: text,
            cues: seg?.cues ?? const [],
            fontSize: _bodyFontSize,
            itemId: _item.id,
            segmentKey: segmentKey,
            focusAnnotationId: ann.id,
            onShareQuote: _shareExistingQuote,
          ),
        );
        return;
      }
    }
    showAnnotationDetailSheet(
      context,
      itemId: _item.id,
      annotation: ann,
      onChanged: _loadAnnotations,
      isPro: _isPro,
      onShare: _shareExistingQuote,
    );
  }

  bool _annotationHasNote(ItemAnnotation ann) =>
      ann.note != null && ann.note!.trim().isNotEmpty;

  RoamSnippet _annotationToRoamSnippet(ItemAnnotation ann) {
    final hasNote = _annotationHasNote(ann);
    return RoamSnippet(
      id: 'local-ann-${ann.id}',
      kind: hasNote ? 'note' : 'highlight',
      text: hasNote ? ann.note!.trim() : ann.selectedText,
      quote: hasNote ? ann.selectedText : null,
      itemId: _item.id,
      annotationId: ann.id,
      annotationSource: ann.source,
      createdAt: ann.createdAt,
    );
  }

  void _showHighlightList() => _showAnnotationList(notesOnly: false);

  void _showNoteAnnotationList() => _showAnnotationList(notesOnly: true);

  /// [notesOnly] false=仅高亮（无批注正文）；true=有批注正文的列表。
  void _showAnnotationList({bool notesOnly = false}) {
    var items = _annotations
        .where((a) => notesOnly ? _annotationHasNote(a) : !_annotationHasNote(a))
        .toList();
    final empty = notesOnly
        ? (_isPro ? '暂无朱批' : '暂无批注')
        : '暂无高亮';
    final emptyHint = notesOnly
        ? '选中正文后可添加批注'
        : '选中正文后点「高亮」即可记下';

    Widget emptyBody(double top, double bottom) {
      return Padding(
        padding: EdgeInsets.fromLTRB(28, top, 28, bottom),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                notesOnly
                    ? Icons.sticky_note_2_outlined
                    : Icons.border_color_outlined,
                size: 28,
                color: _muted.withValues(alpha: 0.45),
              ),
              const SizedBox(height: 14),
              Text(
                empty,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: _muted.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      );
    }

    showAppSideDrawer<void>(
      context: context,
      builder: (drawerContext) {
        final top = MediaQuery.paddingOf(drawerContext).top;
        final bottom = MediaQuery.paddingOf(drawerContext).bottom;
        return StatefulBuilder(
          builder: (context, setDrawerState) {
            if (items.isEmpty) return emptyBody(top, bottom);
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(16, 12 + top, 16, 28 + bottom),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final ann = items[index];
                return RoamQuoteCard(
                  snippet: _annotationToRoamSnippet(ann),
                  // 标注列表完整展示；高亮列表仍截断
                  maxLines: notesOnly ? null : 6,
                  onTap: () {
                    Navigator.pop(drawerContext);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _locateAnnotation(ann);
                    });
                  },
                  onDelete: () async {
                    final ok = await showAppConfirmDialog(
                      drawerContext,
                      title: deleteAnnotationTitle(
                        isPro: _isPro,
                        highlightOnly: !notesOnly,
                      ),
                      message: '删除后不可恢复。',
                      confirmLabel: '删除',
                    );
                    if (ok != true) return;
                    try {
                      await _repo.deleteAnnotation(_item.id, ann.id);
                      if (!mounted) return;
                      setState(() {
                        _annotations =
                            _annotations.where((a) => a.id != ann.id).toList();
                      });
                      setDrawerState(() {
                        items = items.where((a) => a.id != ann.id).toList();
                      });
                      AppToast.show(context, '已删除');
                    } on ApiException catch (e) {
                      if (!mounted) return;
                      AppToast.show(context, e.message);
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _onEditContent() async {
    if (!_item.isSuccess) return;
    if (_annotations.isNotEmpty) {
      final go = await showAppConfirmDialog(
        context,
        title: '编辑正文',
        message: annotationEditBodyWarning(isPro: _isPro),
        confirmLabel: '继续编辑',
        dangerConfirm: false,
      );
      if (go != true || !mounted) return;
    }
    final updated = await showReadingContentEditPage(
      context,
      itemId: _item.id,
      initialContent: _item.content ?? '',
    );
    if (updated == null || !mounted) return;
    setState(() => _item = updated);
    await _loadAnnotations();
    if (!mounted) return;
    AppToast.show(context, '正文已更新');
  }

  Future<void> _onEditTitle() async {
    if (!_item.isSuccess) return;
    final updated = await showReadingTitleEditDialog(
      context,
      itemId: _item.id,
      initialTitle: (_item.title ?? '').trim(),
    );
    if (updated == null || !mounted) return;
    setState(() => _item = updated);
    AppToast.show(context, '标题已更新');
  }

  Future<void> _onNote() async {
    final updated = await showReadingNoteSheet(
      context,
      itemId: _item.id,
      initialNote: _item.note,
      title: (_item.title ?? '').trim(),
      link: _linkToCopy,
      coverUrl: _item.shareCoverUrl,
      pageUrl: _item.sourcePageUrl,
    );
    if (updated != null && mounted) setState(() => _item = updated);
  }

  bool get _hasNote => _item.note != null && _item.note!.trim().isNotEmpty;

  /// 更多操作 sheet（思维导图）；转写请走助手。
  Future<void> _onMore() async {
    final action = await showReadingMoreSheet(
      context,
      mindmapPending: _item.hasMindmapPending,
    );
    if (!mounted || action == null) return;
    switch (action) {
      case ReadingMoreAction.mindmap:
        await _openMindmapSheet();
    }
  }

  void _syncItemTagsMeta(AiTagsMeta meta) {
    if (!mounted) return;
    final prev = _item.aiMeta.tags;
    final finished = prev.isPending && !meta.isPending;
    setState(
      () => _item = _item.withAiMeta(
        AiMeta(
          tags: meta,
          mindmap: _item.aiMeta.mindmap,
          summary: _item.aiMeta.summary,
          model: _item.aiMeta.model,
        ),
      ),
    );
    if (!finished) return;
    if (meta.isSuccess) {
      AppToast.show(
        context,
        aiDoneToast('标签建议已生成', meta.creditsUsed),
      );
    } else if (meta.isEmpty) {
      AppToast.show(
        context,
        aiDoneToast('未找到合适标签', meta.creditsUsed),
      );
    } else if (meta.isFailed) {
      AppToast.show(context, meta.error ?? '标签建议生成失败');
    }
  }

  Future<void> _pollAiSuggestInBackground() async {
    final awaitingTranscript = _item.aiMeta.tags.awaitTranscript;
    final maxAttempts = awaitingTranscript ? 90 : 45;
    final interval = awaitingTranscript
        ? const Duration(seconds: 4)
        : const Duration(seconds: 2);
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      if (!mounted) return;
      try {
        final st = await _repo.getAiSuggestStatus(_item.id);
        if (st.tags.isPending) {
          if (_item.aiMeta.tags.status != st.tags.status ||
              _item.aiMeta.tags.awaitTranscript != st.tags.awaitTranscript) {
            _syncItemTagsMeta(st.tags);
          }
          continue;
        }
        _syncItemTagsMeta(st.tags);
        final item = await _repo.getItem(_item.id);
        if (!mounted) return;
        setState(() => _item = item);
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  void _openTagList(Tag tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: tag.name,
          tagId: tag.isSystem ? null : tag.id,
          loader: ({required limit, required offset}) => _tagsRepo.listTagItems(
            tag.id,
            limit: limit,
            offset: offset,
          ),
        ),
      ),
    );
  }

  Future<void> _openTagsSheet() async {
    await showReadingTagsSheet(
      context,
      itemId: _item.id,
      tagsMeta: _item.aiMeta.tags,
      aiSuggestEnabled: false,
      onTagsMetaChanged: _syncItemTagsMeta,
    );
    if (!mounted) return;
    await _loadItemTags();
  }

  Future<void> _openMindmapSheet() async {
    final mindmap = _item.aiMeta.mindmap;
    final ok = await ensurePlanFeatures(
      context,
      usageRepo: _usageRepo,
      hasResultOrPending:
          mindmap.hasTree || mindmap.isPending || mindmap.isFailed,
      requirements: [
        (has: (f) => f.aiMindmap, tier: UsagePlan.prince),
      ],
    );
    if (!ok || !mounted) return;

    _mindmapPollGen++;
    final title = (_item.title ?? '').trim();
    await showReadingMindmapSheet(
      context,
      itemId: _item.id,
      initialItem: _item,
      sourceTitle: title.isEmpty ? null : title,
      onItemUpdated: (item) {
        if (mounted) setState(() => _item = item);
      },
    );
    if (!mounted) return;
    try {
      final item = await _repo.getItem(_item.id);
      if (mounted) setState(() => _item = item);
    } catch (_) {}
    if (_item.hasMindmapPending) {
      unawaited(_pollMindmap());
    }
  }

  Future<void> _pollMindmap() async {
    final gen = ++_mindmapPollGen;
    final awaitingTranscript = _item.aiMeta.mindmap.awaitTranscript;
    final maxAttempts = awaitingTranscript ? 90 : 45;
    final interval = awaitingTranscript
        ? const Duration(seconds: 4)
        : const Duration(seconds: 2);
    String? lastPhaseFingerprint;
    for (var i = 0; i < maxAttempts; i++) {
      await Future<void>.delayed(interval);
      if (!mounted || gen != _mindmapPollGen) return;
      try {
        final st = await _repo.getMindmapStatus(_item.id);
        if (!mounted || gen != _mindmapPollGen) return;
        if (st.mindmap.isPending) {
          if (st.mindmap.awaitTranscript) {
            final ts = await _repo.getTranscriptStatus(_item.id);
            if (!mounted || gen != _mindmapPollGen) return;
            final merged = Map<String, TranscriptSegment>.from(
              _item.transcriptSegments,
            );
            ts.segments.forEach((key, seg) {
              merged[key] = seg;
            });
            final fp = ts.segments.entries
                .map((e) => '${e.key}:${e.value.phase}:${e.value.phaseLabel}')
                .join('|');
            if (fp != lastPhaseFingerprint ||
                _item.aiMeta.mindmap.status != 'pending') {
              lastPhaseFingerprint = fp;
              final item = await _repo.getItem(_item.id);
              if (!mounted || gen != _mindmapPollGen) return;
              setState(
                () => _item = item
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
          } else if (_item.aiMeta.mindmap.status != 'pending') {
            setState(
              () => _item = _item.withAiMeta(
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
        final item = await _repo.getItem(_item.id);
        if (!mounted || gen != _mindmapPollGen) return;
        setState(() => _item = item);
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

  Future<void> _pollTranscript() async {
    final gen = ++_transcriptPollGen;
    String? lastPhaseFingerprint;
    for (var i = 0; i < 90; i++) {
      // 首轮立刻拉状态，重进页面马上恢复步骤条；之后再间隔轮询
      if (i > 0) {
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      if (!mounted || gen != _transcriptPollGen) return;
      try {
        final st = await _repo.getTranscriptStatus(_item.id);
        if (!mounted || gen != _transcriptPollGen) return;
        if (st.hasPending) {
          // pending 期间合并 segments，让 phaseLabel / 步骤条刷新到面板
          final merged = Map<String, TranscriptSegment>.from(
            _item.transcriptSegments,
          );
          st.segments.forEach((key, seg) {
            merged[key] = seg;
          });
          final fp = st.segments.entries
              .map(
                (e) =>
                    '${e.key}:${e.value.phase}:${e.value.phaseLabel}:${e.value.phaseHint}:${e.value.phaseAt?.toIso8601String()}',
              )
              .join('|');
          if (fp != lastPhaseFingerprint) {
            lastPhaseFingerprint = fp;
            if (!mounted || gen != _transcriptPollGen) return;
            setState(() => _item = _item.withTranscriptSegments(merged));
          }
          continue;
        }
        final item = await _repo.getItem(_item.id);
        if (!mounted || gen != _transcriptPollGen) return;
        setState(() => _item = item);
        final anySuccess = st.segments.values.any((s) => s.isSuccess);
        if (anySuccess) {
          AppToast.show(context, '文稿已生成');
          if (_item.aiMeta.tags.isPending) {
            unawaited(_pollAiSuggestInBackground());
          }
        } else {
          String? errMsg;
          for (final s in st.segments.values) {
            final e = s.error?.trim();
            if (e != null && e.isNotEmpty) {
              errMsg = e;
              break;
            }
          }
          if (errMsg != null) AppToast.show(context, errMsg);
        }
        return;
      } catch (_) {
        // ignore poll errors
      }
    }
  }

  List<({int start, int end, ItemAnnotation ann})> _annotationRanges(
    String text,
  ) {
    final ranges = <({int start, int end, ItemAnnotation ann})>[];
    for (final ann in _annotations) {
      // 文稿标注用独立坐标系，不叠到正文
      if (!ann.isBodySource) continue;
      int? start = ann.startOffset;
      int? end = ann.endOffset;
      if (start == null ||
          end == null ||
          start < 0 ||
          end > text.length ||
          start >= end) {
        final idx = text.indexOf(ann.selectedText);
        if (idx < 0) continue;
        start = idx;
        end = idx + ann.selectedText.length;
      }
      final trimmed = _trimReadingSelectionRange(text, start, end);
      if (trimmed.start >= trimmed.end) continue;
      ranges.add((start: trimmed.start, end: trimmed.end, ann: ann));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    return ranges;
  }

  List<InlineSpan> _bodySpans(String text) {
    return _bodySpansForRange(text, 0, text.length);
  }

  /// [globalStart, globalEnd) 对应 plainText 切片，生成带高亮的 spans（本地坐标）。
  List<InlineSpan> _bodySpansForRange(
    String plainText,
    int globalStart,
    int globalEnd,
  ) {
    if (globalStart >= globalEnd ||
        globalStart < 0 ||
        globalEnd > plainText.length) {
      return [TextSpan(text: '')];
    }
    final localText = plainText.substring(globalStart, globalEnd);
    final ranges = _annotationRanges(plainText)
        .where((r) => r.end > globalStart && r.start < globalEnd)
        .map((r) {
          final trimmed = _trimReadingSelectionRange(
            localText,
            (r.start - globalStart).clamp(0, localText.length),
            (r.end - globalStart).clamp(0, localText.length),
          );
          return (
            start: trimmed.start,
            end: trimmed.end,
            ann: r.ann,
          );
        })
        .where((r) => r.start < r.end)
        .toList();

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final r in ranges) {
      if (r.start < cursor) continue;
      if (r.start > cursor) {
        spans.add(TextSpan(text: localText.substring(cursor, r.start)));
      }
      spans.add(
        TextSpan(
          text: localText.substring(r.start, r.end),
          style: const TextStyle(
            backgroundColor: _highlight,
            color: _text,
          ),
        ),
      );
      cursor = r.end;
    }
    if (cursor < localText.length) {
      spans.add(TextSpan(text: localText.substring(cursor)));
    }
    if (spans.isEmpty) {
      spans.add(TextSpan(text: localText));
    }
    return spans;
  }

  Widget _selectionToolbar(
    BuildContext context,
    EditableTextState editableTextState, {
    int baseOffset = 0,
  }) {
    final value = editableTextState.textEditingValue;
    final sel = _trimReadingTextSelection(value.text, value.selection);
    if (!sel.isValid || sel.isCollapsed) {
      return const SizedBox.shrink();
    }
    final selected = sel.textInside(value.text);
    if (selected.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final anchors = editableTextState.contextMenuAnchors;
    final start = sel.start + baseOffset;
    final end = sel.end + baseOffset;
    return TextSelectionToolbar(
      anchorAbove: anchors.primaryAnchor,
      anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
      toolbarBuilder: (context, child) {
        return Material(
          color: const Color(0xFF1F242E),
          elevation: 6,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(8),
          child: child,
        );
      },
      children: [
        _ToolbarAction(
          label: '高亮',
          onTap: () => _onHighlight(
            editableTextState,
            selected,
            start,
            end,
          ),
        ),
        _ToolbarAction(
          label: addAnnotationLabel(isPro: _isPro),
          onTap: () => _onAddNote(
            editableTextState,
            selected,
            start,
            end,
          ),
        ),
        _ToolbarAction(
          label: '复制',
          onTap: () => _onCopy(editableTextState, selected),
        ),
        _ToolbarAction(
          label: '分享',
          onTapWithOrigin: (origin) => _onShareQuote(
            editableTextState,
            selected,
            shareOrigin: origin,
          ),
        ),
      ],
    );
  }

  EditableTextContextMenuBuilder _toolbarAt(int baseOffset) {
    return (context, state) =>
        _selectionToolbar(context, state, baseOffset: baseOffset);
  }

  @override
  Widget build(BuildContext context) {
    if (_pageLoading && widget.initialItem == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _ReadingTopBar(
              onBack: () => Navigator.of(context).maybePop(),
              showBack: !widget.embedded,
              menuEnabled: false,
              editEnabled: false,
              onEditContent: _onEditContent,
              onEditTitle: _onEditTitle,
              onCopyLink: _copyLink,
              onReparse: _reparseItem,
              onDelete: _confirmDelete,
              onFontSize: _openFontSizeSheet,
              onHighlights: null,
              onAnnotations: null,
            ),
            const Expanded(
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        ),
      );
    }

    if (_pageError != null && widget.initialItem == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            _ReadingTopBar(
              onBack: () => Navigator.of(context).maybePop(),
              showBack: !widget.embedded,
              menuEnabled: false,
              editEnabled: false,
              onEditContent: _onEditContent,
              onEditTitle: _onEditTitle,
              onCopyLink: _copyLink,
              onReparse: _reparseItem,
              onDelete: _confirmDelete,
              onFontSize: _openFontSizeSheet,
              onHighlights: null,
              onAnnotations: null,
            ),
            Expanded(
              child: Center(
                child: Text(
                  _pageError!,
                  style: const TextStyle(color: _muted),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final title =
        _item.title?.isNotEmpty == true ? _item.title! : _item.url;
    final body = _bodyText;
    final canRead = _item.isSuccess;

    final mq = MediaQuery.of(context);
    final topChrome = mq.padding.top + _topBarHeight;
    // 壳内分栏阅读不占 Home Indicator，避免操作栏下方多出一条空白
    final bottomSafe = widget.embedded ? 0.0 : mq.padding.bottom;
    final bottomChrome =
        bottomSafe + _bottomBarGap + _bottomBarHeight;

    return PopScope(
      canPop: widget.embedded || !_shouldNudgeOnLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || widget.embedded) return;
        unawaited(_handleBack());
      },
      child: Scaffold(
      backgroundColor: Colors.white,
      // 感想等弹层自己避让键盘，页面不随 inset 收缩
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          AnimatedPadding(
            duration: _chromeAnim,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(
              top: _chromeVisible ? topChrome : mq.padding.top,
              bottom: _chromeVisible && canRead
                  ? bottomChrome
                  : bottomSafe,
            ),
            child: ListView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                // 避免播放器滚出视口后被 Platform View 回收/暂停（尤其播客音频）
                cacheExtent: mq.size.height * 2,
                padding: canRead &&
                        (_item.isImageGallery || _isTopBarTrueVideo)
                    ? const EdgeInsets.only(bottom: 28)
                    : const EdgeInsets.fromLTRB(22, 18, 22, 28),
                children: [
                  if (canRead && _item.isImageGallery)
                    ..._buildGalleryReadingChildren(
                      title: title,
                      body: body,
                    )
                  else if (canRead && _isTopBarTrueVideo)
                    ..._buildTopBarVideoReadingChildren(
                      title: title,
                      body: body,
                    )
                  else ...[
                    SelectableText(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: _text,
                        height: 1.4,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _metaLine(),
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.4,
                      ),
                    ),
                    if (canRead && _itemTags.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _ArticleTagHashtags(
                        tags: _itemTags,
                        onTap: _openTagList,
                      ),
                    ],
                    const SizedBox(height: 22),
                    if (!canRead) ...[
                      _ReadingStatusChip(status: _item.status),
                      const SizedBox(height: 16),
                      if (_item.isPending)
                        const _ReadingPendingCard()
                      else if (_item.isFailed)
                        _ReadingFailedCard(
                          message: _item.errorMessage,
                          onRetry: _reparseItem,
                        ),
                    ] else ...[
                      if (_item.hasVideo && !_hasInlineVideos) ...[
                        ItemVideoPlayer(
                          key: ValueKey('item-video-${_item.id}'),
                          url: _item.videoUrl!.trim(),
                          coverUrl: _item.coverImageUrl ??
                              (_item.displayImages.isNotEmpty
                                  ? _item.displayImages.first
                                  : null),
                          pageUrl: _item.sourcePageUrl,
                          platform: _item.platform,
                          pageAudio: _pageAudio,
                          onRefreshUrl: _platformNeedsVideoRefresh
                              ? _refreshVideoUrl
                              : null,
                        ),
                        const SizedBox(height: 18),
                      ],
                      ..._buildBodyContent(body, gallery: false),
                      if (_loadingAnns) ...[
                        const SizedBox(height: 16),
                        const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: ClipRect(
                child: AnimatedSlide(
                  duration: _chromeAnim,
                  curve: Curves.easeOutCubic,
                  offset:
                      _chromeVisible ? Offset.zero : const Offset(0, -1),
                  child: _ReadingTopBar(
                    onBack: _handleBack,
                    showBack: !widget.embedded,
                    menuEnabled: true,
                    editEnabled: canRead,
                    showMarkUnread: !_item.isUnread,
                    isPro: _isPro,
                    onEditContent: _onEditContent,
                    onEditTitle: _onEditTitle,
                    onCopyLink: _copyLink,
                    onReparse: _reparseItem,
                    onDelete: _confirmDelete,
                    onMarkUnread: _markAsUnread,
                    onFontSize: _openFontSizeSheet,
                    onHighlights: canRead &&
                            !_item.isImageGallery &&
                            !_isTopBarTrueVideo
                        ? _showHighlightList
                        : null,
                    onAnnotations: canRead &&
                            !_item.isImageGallery &&
                            !_isTopBarTrueVideo
                        ? _showNoteAnnotationList
                        : null,
                    onTranscript: canRead && _showTranscriptHeaderEntry
                        ? () => unawaited(_openTranscriptFromHeader())
                        : null,
                  ),
                ),
              ),
            ),
          ),
          if (canRead)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: ClipRect(
                child: AnimatedSlide(
                  duration: _chromeAnim,
                  curve: Curves.easeOutCubic,
                  offset:
                      _chromeVisible ? Offset.zero : const Offset(0, 1),
                  child: Material(
                    type: MaterialType.transparency,
                    child: SafeArea(
                      top: false,
                      bottom: !widget.embedded,
                      minimum: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          _bottomBarHInset,
                          0,
                          _bottomBarHInset,
                          _bottomBarGap,
                        ),
                        child: SizedBox(
                          height: _bottomBarHeight,
                          child: Row(
                            children: [
                              _AgentActionItem(
                                onTap: () => unawaited(_openAgent()),
                              ),
                              const SizedBox(width: _bottomBarAgentGap),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(
                                      _bottomBarRadius,
                                    ),
                                    border: Border.all(
                                      color: const Color(0xFFE6E8ED),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.06),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      _bottomBarRadius,
                                    ),
                                    child: Row(
                                      children: [
                                        _ActionItem(
                                          icon: Icons.tag_outlined,
                                          label: '标签',
                                          onTap: _openTagsSheet,
                                        ),
                                        _ActionItem(
                                          icon: Icons.edit_note_outlined,
                                          label: '感想',
                                          iconColor:
                                              _hasNote ? _blue : null,
                                          onTap: () =>
                                              unawaited(_onNote()),
                                        ),
                                        _ActionItem(
                                          icon: Icons.more_vert,
                                          label: '更多',
                                          onTap: _onMore,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_shouldNudgeOnLeave)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final velocity = details.primaryVelocity ?? 0;
                  if (velocity > 200) unawaited(_handleBack());
                },
              ),
            ),
        ],
      ),
    ),
    );
  }
}

class _ArticleTagHashtags extends StatelessWidget {
  const _ArticleTagHashtags({
    required this.tags,
    required this.onTap,
    this.color = _brand,
  });

  final List<Tag> tags;
  final ValueChanged<Tag> onTap;
  final Color color;

  static const _brand = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          GestureDetector(
            onTap: () => onTap(tag),
            behavior: HitTestBehavior.opaque,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '#',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: tag.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 普通文章：标题 / 加粗 / 图片随正文混排；文字段可标注。
class _InlineArticleBody extends StatelessWidget {
  const _InlineArticleBody({
    required this.blocks,
    required this.plainText,
    required this.fontSize,
    required this.annotationRanges,
    required this.toolbarAt,
    required this.onTapAnnotation,
    this.onBodyTap,
    this.onSelectionChanged,
    this.focusAnnotationId,
    this.onFocusAnnotationRect,
    this.itemId,
    this.pageUrl,
    this.platform,
    this.pageAudio,
    this.onRefreshInlineVideo,
  });

  final List<ArticleBlock> blocks;
  final String plainText;
  final double fontSize;
  final List<({int start, int end, ItemAnnotation ann})> annotationRanges;
  final EditableTextContextMenuBuilder Function(int baseOffset) toolbarAt;
  final ValueChanged<ItemAnnotation> onTapAnnotation;
  final VoidCallback? onBodyTap;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final int? focusAnnotationId;
  final void Function(Rect localRect, RenderBox stackBox)? onFocusAnnotationRect;
  final int? itemId;
  final String? pageUrl;
  final String? platform;
  final ReadingMediaController? pageAudio;
  final Future<String?> Function(int index)? onRefreshInlineVideo;

  static const _text = Color(0xFF1F242E);
  static const _highlight = Color(0xFFFFF2C7);

  TextStyle get _bodyStyle => TextStyle(
        fontSize: fontSize,
        height: 1.85,
        letterSpacing: 0.2,
        color: _text,
      );

  TextStyle _headingStyle(int level) {
    final size = switch (level) {
      1 => fontSize + 6,
      2 => fontSize + 4,
      3 => fontSize + 2,
      _ => fontSize + 1,
    };
    return TextStyle(
      fontSize: size,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: _text,
      letterSpacing: 0.2,
    );
  }

  ({int start, int end, String visible}) _advance(
    String visible,
    int cursor,
  ) {
    if (visible.isEmpty) {
      return (start: cursor, end: cursor, visible: visible);
    }
    var start = plainText.indexOf(visible, cursor);
    if (start < 0) start = cursor;
    final end = (start + visible.length).clamp(0, plainText.length);
    return (start: start, end: end, visible: visible);
  }

  /// 跳过 plainText 中可见段落后的换行，返回新 cursor。
  int _skipTrailingNewlines(int at) {
    var cursor = at;
    if (cursor + 2 <= plainText.length &&
        plainText.substring(cursor, cursor + 2) == '\n\n') {
      return cursor + 2;
    }
    if (cursor < plainText.length && plainText[cursor] == '\n') {
      return cursor + 1;
    }
    return cursor;
  }

  static bool _hasInlineEmoji(String md) {
    for (final m in ArticleContentBlocks.imageInline.allMatches(md)) {
      final size = ArticleContentBlocks.sizeFromAlt(m.group(1));
      if (ArticleContentBlocks.isInlineEmojiSize(size.$1, size.$2)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var cursor = 0;
    var videoIndex = 0;

    // 相邻纯文本/标题合并为同一 SelectableText；图/视频/表情段打断。
    final islandSpans = <InlineSpan>[];
    final islandBuf = StringBuffer();
    var islandBase = -1;
    var islandContentEnd = -1;

    void flushIsland() {
      if (islandBuf.isEmpty) return;
      final text = islandBuf.toString();
      final base = islandBase < 0 ? 0 : islandBase;
      final localAnns = annotationRanges
          .where((r) => r.end > base && r.start < base + text.length)
          .map((r) {
            final trimmed = _trimReadingSelectionRange(
              text,
              (r.start - base).clamp(0, text.length),
              (r.end - base).clamp(0, text.length),
            );
            return (
              start: trimmed.start,
              end: trimmed.end,
              ann: r.ann,
            );
          })
          .where((r) => r.start < r.end)
          .toList();

      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(
        _AnnotatedBodyStack(
          text: text,
          spans: islandSpans.isEmpty
              ? [TextSpan(text: text, style: _bodyStyle)]
              : List<InlineSpan>.from(islandSpans),
          annotations: localAnns,
          contextMenuBuilder: toolbarAt(base),
          onTapAnnotation: onTapAnnotation,
          onBodyTap: onBodyTap,
          onSelectionChanged: onSelectionChanged,
          textStyle: _bodyStyle,
          focusAnnotationId: focusAnnotationId,
          onFocusAnnotationRect: onFocusAnnotationRect,
        ),
      );
      islandSpans.clear();
      islandBuf.clear();
      islandBase = -1;
      islandContentEnd = -1;
    }

    void appendSelectableSegment({
      required String visible,
      required int posStart,
      required int posEnd,
      required List<InlineSpan> spans,
      required TextStyle fallbackStyle,
    }) {
      if (islandBuf.isNotEmpty) {
        final sep = (posStart > islandContentEnd)
            ? plainText.substring(islandContentEnd, posStart)
            : '\n\n';
        if (sep.isNotEmpty) {
          islandBuf.write(sep);
          islandSpans.add(TextSpan(text: sep, style: _bodyStyle));
        }
      } else {
        islandBase = posStart;
      }
      if (spans.isEmpty) {
        islandSpans.add(TextSpan(text: visible, style: fallbackStyle));
      } else {
        islandSpans.addAll(spans);
      }
      islandBuf.write(visible);
      islandContentEnd = posEnd;
    }

    void emitEmojiParagraph({
      required String md,
      required String visible,
      required int posStart,
      required int posEnd,
    }) {
      flushIsland();
      final localAnns = annotationRanges
          .where((r) => r.end > posStart && r.start < posEnd)
          .map((r) {
            final trimmed = _trimReadingSelectionRange(
              visible,
              (r.start - posStart).clamp(0, visible.length),
              (r.end - posStart).clamp(0, visible.length),
            );
            return (
              start: trimmed.start,
              end: trimmed.end,
              ann: r.ann,
            );
          })
          .where((r) => r.start < r.end)
          .toList();
      final bodyStyle = _bodyStyle;
      final spans = ArticleMarkdown.inlineSpans(
        md,
        style: bodyStyle,
        highlights: [
          for (final a in localAnns) (start: a.start, end: a.end),
        ],
        highlightColor: _highlight,
        imageBuilder: (url, w, h) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: _InlineEmoji(
            url: url,
            width: w,
            height: h,
            pageUrl: pageUrl,
          ),
        ),
      );
      if (children.isNotEmpty) children.add(const SizedBox(height: 14));
      children.add(
        _AnnotatedBodyStack(
          text: visible,
          spans: spans.isEmpty
              ? [TextSpan(text: '', style: bodyStyle)]
              : spans,
          annotations: localAnns,
          contextMenuBuilder: toolbarAt(posStart),
          onTapAnnotation: onTapAnnotation,
          onBodyTap: onBodyTap,
          onSelectionChanged: onSelectionChanged,
          textStyle: bodyStyle,
          focusAnnotationId: focusAnnotationId,
          onFocusAnnotationRect: onFocusAnnotationRect,
        ),
      );
    }

    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];

      if (block is ArticleVideoBlock) {
        flushIsland();
        if (children.isNotEmpty) children.add(const SizedBox(height: 18));
        final index = videoIndex++;
        children.add(
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = (w * 9 / 16).clamp(180.0, 280.0);
              return ItemVideoPlayer(
                key: ValueKey('body-video-${itemId ?? 0}-$index'),
                url: block.url,
                coverUrl: block.posterUrl,
                pageUrl: pageUrl,
                platform: platform,
                pageAudio: pageAudio,
                height: h,
                onRefreshUrl: onRefreshInlineVideo == null
                    ? null
                    : () => onRefreshInlineVideo!(index),
              );
            },
          ),
        );
        continue;
      }

      if (block is ArticleImageBlock) {
        flushIsland();
        if (children.isNotEmpty) children.add(const SizedBox(height: 18));
        children.add(
          _ReadingInlineImage(
            url: block.url,
            pageUrl: pageUrl,
            hintWidth: block.width,
            hintHeight: block.height,
          ),
        );
        continue;
      }

      if (block is ArticleHeadingBlock) {
        final md = block.text.trim();
        final visible = ArticleMarkdown.stripMarkers(md);
        if (visible.isEmpty) continue;
        final pos = _advance(visible, cursor);
        cursor = _skipTrailingNewlines(pos.end);

        final segAnns = annotationRanges
            .where((r) => r.end > pos.start && r.start < pos.end)
            .map((r) {
              final trimmed = _trimReadingSelectionRange(
                visible,
                (r.start - pos.start).clamp(0, visible.length),
                (r.end - pos.start).clamp(0, visible.length),
              );
              return (start: trimmed.start, end: trimmed.end);
            })
            .where((r) => r.start < r.end)
            .toList();
        final style = _headingStyle(block.level);
        final spans = ArticleMarkdown.inlineSpans(
          md,
          style: style,
          highlights: segAnns,
          highlightColor: _highlight,
        );
        appendSelectableSegment(
          visible: visible,
          posStart: pos.start,
          posEnd: pos.end,
          spans: spans,
          fallbackStyle: style,
        );
        continue;
      }

      if (block is! ArticleTextBlock) continue;

      final mdParagraphs = ArticleBodyText.splitParagraphs(block.text);
      for (final md in mdParagraphs) {
        final visible = ArticleMarkdown.visiblePlain(md);
        if (visible.isEmpty) continue;

        final pos = _advance(visible, cursor);
        cursor = _skipTrailingNewlines(pos.end);

        if (_hasInlineEmoji(md)) {
          emitEmojiParagraph(
            md: md,
            visible: visible,
            posStart: pos.start,
            posEnd: pos.end,
          );
          continue;
        }

        final segAnns = annotationRanges
            .where((r) => r.end > pos.start && r.start < pos.end)
            .map((r) {
              final trimmed = _trimReadingSelectionRange(
                visible,
                (r.start - pos.start).clamp(0, visible.length),
                (r.end - pos.start).clamp(0, visible.length),
              );
              return (start: trimmed.start, end: trimmed.end);
            })
            .where((r) => r.start < r.end)
            .toList();
        final bodyStyle = _bodyStyle;
        final spans = ArticleMarkdown.inlineSpans(
          md,
          style: bodyStyle,
          highlights: segAnns,
          highlightColor: _highlight,
        );
        appendSelectableSegment(
          visible: visible,
          posStart: pos.start,
          posEnd: pos.end,
          spans: spans,
          fallbackStyle: bodyStyle,
        );
      }
    }

    flushIsland();

    if (children.isEmpty) {
      return Text(
        '暂无正文',
        style: TextStyle(fontSize: fontSize, color: const Color(0xFF737A85)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// 正文插图：有原文宽高且小于栏宽时按声明尺寸展示；
/// 否则与正文同宽，按比例定高。
class _ReadingInlineImage extends StatefulWidget {
  const _ReadingInlineImage({
    required this.url,
    this.pageUrl,
    this.hintWidth,
    this.hintHeight,
  });

  final String url;
  final String? pageUrl;
  final double? hintWidth;
  final double? hintHeight;

  @override
  State<_ReadingInlineImage> createState() => _ReadingInlineImageState();
}

class _ReadingInlineImageState extends State<_ReadingInlineImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  double? _decodedW;
  double? _decodedH;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant _ReadingInlineImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url || oldWidget.pageUrl != widget.pageUrl) {
      _stop();
      _decodedW = null;
      _decodedH = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _listen() {
    final resolved = resolveMediaUrl(widget.url);
    final provider = NetworkImage(
      resolved,
      headers: mediaHttpHeadersFor(resolved, pageUrl: widget.pageUrl),
    );
    _stream = provider.resolve(const ImageConfiguration());
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _decodedW = info.image.width.toDouble();
          _decodedH = info.image.height.toDouble();
        });
      },
      onError: (_, __) {},
    );
    _stream!.addListener(_listener!);
  }

  void _stop() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final declaredW = widget.hintWidth;
        final declaredH = widget.hintHeight;
        final aspect = (declaredW != null &&
                declaredH != null &&
                declaredW > 0 &&
                declaredH > 0)
            ? declaredH / declaredW
            : (_decodedW != null &&
                    _decodedH != null &&
                    _decodedW! > 0)
                ? _decodedH! / _decodedW!
                : null;
        // 原文声明宽度小于栏宽：按 CSS 像素展示；否则铺满栏宽。
        final width = (declaredW != null &&
                declaredW > 0 &&
                declaredW < maxW)
            ? declaredW
            : maxW;
        final height = aspect != null ? width * aspect : null;
        final image = Image.network(
          resolveMediaUrl(widget.url),
          width: width,
          height: height,
          fit: BoxFit.fitWidth,
          alignment: Alignment.center,
          headers: mediaHttpHeadersFor(
            resolveMediaUrl(widget.url),
            pageUrl: widget.pageUrl,
          ),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => SizedBox(
            width: width,
            height: height ?? 72,
            child: const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Color(0xFFB2B8BF),
                size: 30,
              ),
            ),
          ),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: width,
              height: height ?? 160,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
        );
        if (width >= maxW) return image;
        return Align(alignment: Alignment.centerLeft, child: image);
      },
    );
  }
}

/// 行内表情：跟后面的文字同一行。
class _InlineEmoji extends StatelessWidget {
  const _InlineEmoji({
    required this.url,
    required this.width,
    required this.height,
    this.pageUrl,
  });

  final String url;
  final double width;
  final double height;
  final String? pageUrl;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Image.network(
        resolveMediaUrl(url),
        width: width,
        height: height,
        fit: BoxFit.contain,
        headers: mediaHttpHeadersFor(
          resolveMediaUrl(url),
          pageUrl: pageUrl,
        ),
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => SizedBox(width: width, height: height),
      ),
    );
  }
}

/// 选区末尾的换行/空白：Flutter 会画满整行，需从选区与高亮范围里去掉。
bool _isReadingSelectionTrimUnit(int unit) {
  return unit == 0x0A || // \n
      unit == 0x0D || // \r
      unit == 0x20 || // space
      unit == 0x09 || // \t
      unit == 0x3000; // ideographic space
}

({int start, int end}) _trimReadingSelectionRange(
  String text,
  int start,
  int end,
) {
  var s = start.clamp(0, text.length);
  var e = end.clamp(0, text.length);
  if (e < s) {
    final t = s;
    s = e;
    e = t;
  }
  while (e > s && _isReadingSelectionTrimUnit(text.codeUnitAt(e - 1))) {
    e--;
  }
  while (s < e && _isReadingSelectionTrimUnit(text.codeUnitAt(s))) {
    s++;
  }
  return (start: s, end: e);
}

TextSelection _trimReadingTextSelection(String text, TextSelection sel) {
  if (!sel.isValid || sel.isCollapsed) return sel;
  final t = _trimReadingSelectionRange(text, sel.start, sel.end);
  if (t.start == sel.start && t.end == sel.end) return sel;
  if (t.start >= t.end) {
    return TextSelection.collapsed(offset: t.start);
  }
  if (sel.baseOffset <= sel.extentOffset) {
    return TextSelection(baseOffset: t.start, extentOffset: t.end);
  }
  return TextSelection(baseOffset: t.end, extentOffset: t.start);
}

/// 正文可选中；批注热区与批注图标用 Stack 绝对定位，不抢 SelectableText 手势状态。
class _AnnotatedBodyStack extends StatefulWidget {
  const _AnnotatedBodyStack({
    required this.text,
    required this.spans,
    required this.annotations,
    required this.contextMenuBuilder,
    required this.onTapAnnotation,
    this.onBodyTap,
    this.onSelectionChanged,
    this.textStyle,
    this.focusAnnotationId,
    this.onFocusAnnotationRect,
  });

  final String text;
  final List<InlineSpan> spans;
  final List<({int start, int end, ItemAnnotation ann})> annotations;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final ValueChanged<ItemAnnotation> onTapAnnotation;
  final VoidCallback? onBodyTap;
  final ValueChanged<TextSelection>? onSelectionChanged;
  final TextStyle? textStyle;
  final int? focusAnnotationId;
  final void Function(Rect localRect, RenderBox stackBox)? onFocusAnnotationRect;

  static const _text = Color(0xFF1F242E);
  static const _blue = Color(0xFF2F6FED);
  static const _highlight = Color(0xFFFFF2C7);

  static const bodyStyle = TextStyle(
    fontSize: 15,
    height: 1.85,
    letterSpacing: 0.2,
    color: _text,
  );

  @override
  State<_AnnotatedBodyStack> createState() => _AnnotatedBodyStackState();
}

class _AnnotatedBodyStackState extends State<_AnnotatedBodyStack> {
  final GlobalKey _textKey = GlobalKey();
  final List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> _hits = [];
  double? _laidOutWidth;
  int _measureToken = 0;
  int _measureMisses = 0;
  bool _clampingSelection = false;

  @override
  void didUpdateWidget(covariant _AnnotatedBodyStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.annotations.length != widget.annotations.length ||
        oldWidget.spans.length != widget.spans.length ||
        oldWidget.textStyle?.fontSize != widget.textStyle?.fontSize ||
        oldWidget.focusAnnotationId != widget.focusAnnotationId ||
        !_sameAnnotationIds(oldWidget.annotations, widget.annotations)) {
      _laidOutWidth = null;
      _measureMisses = 0;
    }
  }

  bool _sameAnnotationIds(
    List<({int start, int end, ItemAnnotation ann})> a,
    List<({int start, int end, ItemAnnotation ann})> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].ann.id != b[i].ann.id) return false;
      final aNote = a[i].ann.note?.trim() ?? '';
      final bNote = b[i].ann.note?.trim() ?? '';
      if (aNote != bNote) return false;
      if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
    }
    return true;
  }

  void _scheduleMeasure() {
    final token = ++_measureToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _measureToken) return;
      _measure();
    });
  }

  RenderEditable? _findRenderEditable() {
    final root = _textKey.currentContext?.findRenderObject();
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? found;
    void visit(RenderObject child) {
      if (found != null) return;
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visit);
    }

    root.visitChildren(visit);
    return found;
  }

  EditableTextState? _findEditableTextState() {
    final ctx = _textKey.currentContext;
    if (ctx == null) return null;
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    ctx.visitChildElements(visit);
    if (found == null && ctx is StatefulElement && ctx.state is EditableTextState) {
      found = ctx.state as EditableTextState;
    }
    return found;
  }

  /// 段末 `\n` 被划进选区时仍可能多出空白盒；同步收紧到正文末字。
  void _onSelectionChanged(TextSelection selection, SelectionChangedCause? cause) {
    if (_clampingSelection) {
      widget.onSelectionChanged?.call(selection);
      return;
    }
    if (!selection.isValid || selection.isCollapsed) {
      widget.onSelectionChanged?.call(selection);
      return;
    }
    final state = _findEditableTextState();
    final text = state?.textEditingValue.text ?? widget.text;
    final clamped = _trimReadingTextSelection(text, selection);
    if (clamped.start == selection.start && clamped.end == selection.end) {
      widget.onSelectionChanged?.call(selection);
      return;
    }
    widget.onSelectionChanged?.call(clamped);
    if (state == null) return;
    _clampingSelection = true;
    state.userUpdateTextEditingValue(
      state.textEditingValue.copyWith(selection: clamped),
      cause ?? SelectionChangedCause.toolbar,
    );
    _clampingSelection = false;
  }

  /// 去掉选区末尾换行/空白对应的空盒子，避免图标落到段间距里。
  List<TextBox> _meaningfulBoxes(List<TextBox> boxes) {
    return boxes
        .where((b) => (b.right - b.left) > 1.0 && (b.bottom - b.top) > 1.0)
        .toList(growable: false);
  }

  void _measure() {
    if (widget.annotations.isEmpty) {
      if (_hits.isNotEmpty) {
        setState(() => _hits.clear());
      }
      return;
    }

    final editable = _findRenderEditable();
    final stackBox = context.findRenderObject() as RenderBox?;
    if (editable == null || stackBox == null || !stackBox.hasSize) {
      if (_measureMisses < 10) {
        _measureMisses++;
        _scheduleMeasure();
      }
      return;
    }
    _measureMisses = 0;

    // RenderEditable 相对 Stack 的偏移（SelectableText 内部可能有 inset）
    final origin = editable.localToGlobal(Offset.zero, ancestor: stackBox);

    final next = <({Rect rect, ItemAnnotation ann, bool showNoteIcon})>[];
    for (final r in widget.annotations) {
      final trimmed = _trimReadingSelectionRange(widget.text, r.start, r.end);
      if (trimmed.start >= trimmed.end) continue;
      final raw = editable.getBoxesForSelection(
        TextSelection(
          baseOffset: trimmed.start,
          extentOffset: trimmed.end,
        ),
      );
      final boxes = _meaningfulBoxes(raw);
      if (boxes.isEmpty) continue;

      final hasNote =
          r.ann.note != null && r.ann.note!.trim().isNotEmpty;
      for (var i = 0; i < boxes.length; i++) {
        final box = boxes[i];
        next.add((
          rect: Rect.fromLTRB(
            origin.dx + box.left,
            origin.dy + box.top,
            origin.dx + box.right,
            origin.dy + box.bottom,
          ),
          ann: r.ann,
          showNoteIcon: hasNote && i == boxes.length - 1,
        ));
      }
    }

    if (!_hits.equal(next) && mounted) {
      setState(() {
        _hits
          ..clear()
          ..addAll(next);
      });
    }

    final focusId = widget.focusAnnotationId;
    final onFocus = widget.onFocusAnnotationRect;
    if (focusId != null && onFocus != null) {
      for (final h in next) {
        if (h.ann.id == focusId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            onFocus(h.rect, stackBox);
          });
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        if (_laidOutWidth != w) {
          _laidOutWidth = w;
        }
        // 每帧后按真实 RenderEditable 量一次，避免 TextPainter 与真机排版不一致
        final hasEmoji = widget.spans.any((s) => s is WidgetSpan);
        if (!hasEmoji) _scheduleMeasure();
        final rich = TextSpan(
          style: widget.textStyle ?? _AnnotatedBodyStack.bodyStyle,
          children: widget.spans,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            TextSelectionTheme(
              data: const TextSelectionThemeData(
                selectionColor: _AnnotatedBodyStack._highlight,
                selectionHandleColor: _AnnotatedBodyStack._blue,
              ),
              // SelectableText 不绘制 WidgetSpan，表情段改用 Text.rich。
              child: hasEmoji
                  ? Text.rich(rich, textAlign: TextAlign.start)
                  : SelectableText.rich(
                      rich,
                      key: _textKey,
                      textAlign: TextAlign.justify,
                      // width tight：短行不拉满到最宽行；height 含行距：避免行间露白缝。
                      selectionWidthStyle: BoxWidthStyle.tight,
                      selectionHeightStyle:
                          BoxHeightStyle.includeLineSpacingMiddle,
                      contextMenuBuilder: widget.contextMenuBuilder,
                      onTap: widget.onBodyTap,
                      onSelectionChanged: _onSelectionChanged,
                    ),
            ),
            // 透明热区盖住高亮，稳定响应点击（不与选区手势打架）
            for (final hit in _hits)
              Positioned(
                left: hit.rect.left,
                top: hit.rect.top,
                width: hit.rect.width,
                height: hit.rect.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onTapAnnotation(hit.ann),
                  child: const ColoredBox(color: Color(0x00000000)),
                ),
              ),
            for (final hit in _hits)
              if (hit.showNoteIcon)
                Positioned(
                  left: hit.rect.right - 2,
                  top: hit.rect.top + (hit.rect.height - 12) / 2,
                  child: const IgnorePointer(
                    child: Icon(
                      Icons.sticky_note_2_outlined,
                      size: 16,
                      color: _AnnotatedBodyStack._blue,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}

extension on List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> {
  bool equal(
    List<({Rect rect, ItemAnnotation ann, bool showNoteIcon})> other,
  ) {
    if (length != other.length) return false;
    for (var i = 0; i < length; i++) {
      final a = this[i];
      final b = other[i];
      if (a.ann.id != b.ann.id || a.showNoteIcon != b.showNoteIcon) {
        return false;
      }
      if ((a.rect.left - b.rect.left).abs() > 0.5 ||
          (a.rect.top - b.rect.top).abs() > 0.5 ||
          (a.rect.width - b.rect.width).abs() > 0.5 ||
          (a.rect.height - b.rect.height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }
}

/// 深色圆角工具条「高亮 / 加批注 / 复制 / 分享」
class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.label,
    this.onTap,
    this.onTapWithOrigin,
  }) : assert(onTap != null || onTapWithOrigin != null);

  final String label;
  final VoidCallback? onTap;
  final void Function(Rect? origin)? onTapWithOrigin;

  Rect? _origin(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.isEmpty) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        final report = onTapWithOrigin;
        if (report != null) {
          report(_origin(context));
          return;
        }
        onTap?.call();
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ReadingTopBar extends StatelessWidget {
  const _ReadingTopBar({
    required this.onBack,
    required this.onCopyLink,
    required this.onReparse,
    required this.onDelete,
    required this.onEditContent,
    required this.onEditTitle,
    required this.onFontSize,
    this.onMarkUnread,
    this.onHighlights,
    this.onAnnotations,
    this.onTranscript,
    this.showBack = true,
    this.menuEnabled = true,
    this.editEnabled = false,
    this.showMarkUnread = false,
    this.isPro = false,
  });

  final VoidCallback onBack;
  final VoidCallback onCopyLink;
  final VoidCallback onReparse;
  final VoidCallback onDelete;
  final VoidCallback onEditContent;
  final VoidCallback onEditTitle;
  final VoidCallback onFontSize;
  final VoidCallback? onMarkUnread;
  final VoidCallback? onHighlights;
  final VoidCallback? onAnnotations;
  /// 视频类文稿入口
  final VoidCallback? onTranscript;
  final bool showBack;
  final bool menuEnabled;
  final bool editEnabled;
  final bool showMarkUnread;
  final bool isPro;

  static const _text = Color(0xFF1F242E);
  static const _danger = Color(0xFFE34D59);

  @override
  Widget build(BuildContext context) {
    final noteLabel = annotationSectionTitle(isPro: isPro);
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 4),
            child: Row(
              children: [
                if (showBack)
                  TextButton.icon(
                    onPressed: onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: _text,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 28),
                    label: const Text(
                      '返回',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
                    ),
                  )
                else
                  const SizedBox(width: 8),
                const Spacer(),
                if (onHighlights != null)
                  IconButton(
                    tooltip: '高亮',
                    onPressed: onHighlights,
                    icon: const Icon(
                      Icons.border_color_outlined,
                      size: 22,
                      color: _text,
                    ),
                  ),
                if (onAnnotations != null)
                  IconButton(
                    tooltip: noteLabel,
                    onPressed: onAnnotations,
                    icon: const Icon(
                      Icons.sticky_note_2_outlined,
                      size: 22,
                      color: _text,
                    ),
                  ),
                if (onTranscript != null)
                  IconButton(
                    tooltip: '文稿',
                    onPressed: onTranscript,
                    icon: const Icon(
                      Icons.article_outlined,
                      size: 22,
                      color: _text,
                    ),
                  ),
                IconButton(
                  tooltip: '文字大小',
                  onPressed: onFontSize,
                  icon: const Text(
                    'Aa',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _text,
                      height: 1,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: menuEnabled,
                  tooltip: '更多',
                  offset: const Offset(0, 40),
                  elevation: 8,
                  color: Colors.white,
                  shadowColor: Colors.black.withValues(alpha: 0.14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE6E8EB)),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 148, maxWidth: 168),
                  onSelected: (value) {
                    if (value == 'editTitle') onEditTitle();
                    if (value == 'edit') onEditContent();
                    if (value == 'unread') onMarkUnread?.call();
                    if (value == 'copy') onCopyLink();
                    if (value == 'reparse') onReparse();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    if (editEnabled)
                      const PopupMenuItem<String>(
                        value: 'editTitle',
                        height: 44,
                        child: Text(
                          '修改标题',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _text,
                          ),
                        ),
                      ),
                    if (editEnabled)
                      const PopupMenuItem<String>(
                        value: 'edit',
                        height: 44,
                        child: Text(
                          '编辑正文',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _text,
                          ),
                        ),
                      ),
                    if (showMarkUnread)
                      PopupMenuItem<String>(
                        value: 'unread',
                        height: 44,
                        child: Text(
                          markAsUnreadLabel(isPro: isPro),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _text,
                          ),
                        ),
                      ),
                    const PopupMenuItem<String>(
                      value: 'copy',
                      height: 44,
                      child: Text(
                        '复制链接',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _text,
                        ),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'reparse',
                      height: 44,
                      child: Text(
                        '重新解析',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _text,
                        ),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      height: 44,
                      child: Text(
                        '删除',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: _danger,
                        ),
                      ),
                    ),
                  ],
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Text(
                        '⋯',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _text,
                          height: 1,
                        ),
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

class _ReadingStatusChip extends StatelessWidget {
  const _ReadingStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    switch (status) {
      case 'success':
        bg = const Color(0xFFE5F7EB);
        fg = const Color(0xFF26804D);
        label = '解析完成';
      case 'failed':
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFFE34D59);
        label = '解析失败';
      default:
        bg = const Color(0xFFFFF3E6);
        fg = const Color(0xFFD97706);
        label = '正在解析…';
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: fg,
            height: 17 / 12,
          ),
        ),
      ),
    );
  }
}

class _ReadingPendingCard extends StatelessWidget {
  const _ReadingPendingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skel(height: 14, width: double.infinity),
        const SizedBox(height: 12),
        _skel(height: 14, width: 220),
        const SizedBox(height: 12),
        _skel(height: 14, width: 160),
        const SizedBox(height: 20),
        _skel(height: 14, width: double.infinity),
        const SizedBox(height: 12),
        _skel(height: 14, width: 200),
      ],
    );
  }

  Widget _skel({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F5),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

class _ReadingFailedCard extends StatelessWidget {
  const _ReadingFailedCard({this.message, required this.onRetry});

  final String? message;
  final VoidCallback onRetry;

  static const _blue = Color(0xFF2F6FED);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '无法解析该链接的正文',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          (message != null && message!.isNotEmpty)
              ? message!
              : '请稍后重试。第一期不支持打开原文。',
          style: const TextStyle(
            fontSize: 14,
            color: _muted,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: _blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '重试解析',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

/// 底栏助手入口：胶囊外独立圆钮，✦ 与「助手」都包在圆内。
class _AgentActionItem extends StatelessWidget {
  const _AgentActionItem({required this.onTap});

  final VoidCallback onTap;

  static const _brand = Color(0xFF2F6FED);
  static const _size = _ItemReadingPageState._bottomBarHeight;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      overlayColor: WidgetStateProperty.all(Colors.transparent),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE6E8ED)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const SizedBox(
          width: _size,
          height: _size,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '✦',
                style: TextStyle(
                  fontSize: 16,
                  height: 1,
                  color: _brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '助手',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: _brand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
    this.iconColor,
    this.iconSize = 24,
  }) : assert(icon != null || iconWidget != null);

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;
  final double iconSize;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            const Spacer(),
            SizedBox(
              width: 24,
              height: 24,
              child: Center(
                child: iconWidget ??
                    Icon(
                      icon,
                      size: iconSize,
                      color: iconColor ?? _text,
                    ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                height: 1.2,
                color: iconColor ?? _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

