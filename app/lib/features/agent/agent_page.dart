import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_chat_cache.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/agent/agent_models.dart';
import 'package:super_collection/features/agent/agent_repository.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 私人助手（P1：查收藏 + 出处）
///
/// [focusItemId] / [focusItem]：从阅读页带入时展示当前篇，并每轮锚定摘录。
class AgentPage extends StatefulWidget {
  const AgentPage({
    super.key,
    this.focusItemId,
    this.focusItem,
  });

  final int? focusItemId;
  final CollectionItem? focusItem;

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  static const _bg = Colors.white;
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE8F0FF);

  final _repo = AgentRepository();
  final _auth = AuthRepository();
  final _itemsRepo = ItemsRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  int? _conversationId;
  final List<AgentMessage> _messages = [];
  bool _booting = true;
  bool _sending = false;
  /// 已有流式 token 时隐藏「思考中」
  bool _streamLive = false;
  String? _error;
  CollectionItem? _focusItem;
  /// 已勾选进输入区的出处（以 chip 展示，发送时拼进正文）
  final Map<int, AgentCitation> _pickedCitations = {};
  int? _cacheUserId;

  int? get _focusItemId =>
      widget.focusItemId ?? widget.focusItem?.id ?? _focusItem?.id;

  @override
  void initState() {
    super.initState();
    _focusItem = widget.focusItem;
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _ensureFocusItem() async {
    if (_focusItem != null) return;
    final id = widget.focusItemId;
    if (id == null) return;
    try {
      final item = await _itemsRepo.getItem(id);
      if (!mounted) return;
      setState(() => _focusItem = item);
    } catch (_) {
      // 锚定请求仍可用 id；卡片展示失败则静默
    }
  }

  Future<void> _persistCache() async {
    final userId = _cacheUserId;
    final convId = _conversationId;
    if (userId == null || convId == null) return;
    await AgentChatCache.write(
      userId: userId,
      focusItemId: _focusItemId,
      conversationId: convId,
      messages: _messages,
    );
  }

  Future<void> _bootstrap() async {
    final session = await _auth.readSession();
    _cacheUserId = session?.userId;

    // 有本地缓存先上屏，免每次全屏 loading
    var showedCache = false;
    if (_cacheUserId != null) {
      final cached = await AgentChatCache.read(
        userId: _cacheUserId!,
        focusItemId: _focusItemId,
      );
      if (cached != null &&
          cached.conversationId > 0 &&
          mounted) {
        setState(() {
          _conversationId = cached.conversationId;
          _messages
            ..clear()
            ..addAll(cached.messages.where((m) => m.isUser || m.isAssistant));
          _booting = false;
          _error = null;
        });
        showedCache = true;
        if (_messages.isNotEmpty) {
          unawaited(_scrollToEndSettled());
        }
      }
    }

    if (!showedCache && mounted) {
      setState(() {
        _booting = true;
        _error = null;
      });
    }

    try {
      await _ensureFocusItem();
      // 阅读页：该篇专属会话；首页/收藏：全局会话（互不串）
      final conv = await _repo.ensureConversation(
        focusItemId: _focusItemId,
        title: _focusItem?.title,
      );
      if (!mounted) return;
      final detail = await _repo.getConversation(conv.id);
      if (!mounted) return;
      final next = detail.messages
          .where((m) => m.isUser || m.isAssistant)
          .toList(growable: false);
      setState(() {
        _conversationId = detail.conversation.id;
        _messages
          ..clear()
          ..addAll(next);
        _booting = false;
        _error = null;
      });
      unawaited(_persistCache());
      if (_messages.isNotEmpty) {
        // 出处卡/Markdown 多帧才撑开高度，单次 jump 会停在半截
        unawaited(_scrollToEndSettled());
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // 已有缓存可继续聊；无缓存才当错误页
      setState(() {
        _booting = false;
        if (!showedCache) _error = e.message;
      });
      if (!showedCache) await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        if (!showedCache) _error = '加载失败';
      });
    }
  }

  Future<void> _ensureConversation() async {
    if (_conversationId != null) return;
    final conv = await _repo.ensureConversation(
      focusItemId: _focusItemId,
      title: _focusItem?.title,
    );
    _conversationId = conv.id;
  }

  Future<void> _send([String? preset]) async {
    final typed = (preset ?? _input.text).trim();
    final refs = _pickedCitations.values
        .map((c) => '「${c.title.trim()}」')
        .where((s) => s.length > 2)
        .join(' ');
    final text = preset != null
        ? typed
        : [refs, typed].where((s) => s.isNotEmpty).join(' ').trim();
    if (text.isEmpty || _sending) return;

    final allowed = await ensurePlanFeatures(
      context,
      requirements: [
        (has: (f) => f.aiAgent, tier: UsagePlan.prince),
      ],
    );
    if (!allowed || !mounted) return;

    setState(() {
      _sending = true;
      _streamLive = false;
      _pickedCitations.clear();
    });
    if (preset == null) _input.clear();

    // 乐观展示用户消息 + 流式助手占位
    final optimisticUser = AgentMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      role: 'user',
      content: text,
    );
    final streamAssistantId = -DateTime.now().millisecondsSinceEpoch - 1;
    setState(() => _messages.add(optimisticUser));
    _scrollToEnd();

    try {
      await _ensureConversation();
      final id = _conversationId!;
      final result = await _repo.sendMessageStream(
        conversationId: id,
        content: text,
        focusItemId: _focusItemId,
        onUser: (user) {
          if (!mounted) return;
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.id == optimisticUser.id);
            if (idx >= 0) _messages[idx] = user;
          });
        },
        onToken: (delta) {
          if (!mounted) return;
          setState(() {
            if (!_streamLive) {
              _streamLive = true;
              _messages.add(
                AgentMessage(
                  id: streamAssistantId,
                  role: 'assistant',
                  content: delta,
                ),
              );
            } else {
              final idx =
                  _messages.indexWhere((m) => m.id == streamAssistantId);
              if (idx >= 0) {
                _messages[idx] = _messages[idx].copyWith(
                  content: _messages[idx].content + delta,
                );
              }
            }
          });
          _scrollToEnd();
        },
      );
      if (!mounted) return;
      setState(() {
        final uIdx =
            _messages.indexWhere((m) => m.id == optimisticUser.id);
        if (uIdx >= 0) {
          _messages[uIdx] = result.userMessage;
        } else {
          final lastUser = _messages.lastIndexWhere((m) => m.isUser);
          if (lastUser >= 0) {
            _messages[lastUser] = result.userMessage;
          }
        }
        final aIdx =
            _messages.indexWhere((m) => m.id == streamAssistantId);
        if (aIdx >= 0) {
          _messages[aIdx] = result.assistantMessage;
        } else {
          _messages.add(result.assistantMessage);
        }
        _sending = false;
        _streamLive = false;
      });
      unawaited(_persistCache());
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere(
          (m) => m.id == optimisticUser.id || m.id == streamAssistantId,
        );
        _sending = false;
        _streamLive = false;
      });
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere(
          (m) => m.id == optimisticUser.id || m.id == streamAssistantId,
        );
        _sending = false;
        _streamLive = false;
      });
      AppToast.show(context, '发送失败，请重试');
    }
  }

  /// 正序列表：内容少时从顶部起；溢出后滚到最新。
  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      if (jump) {
        _scroll.jumpTo(max);
      } else {
        _scroll.animateTo(
          max,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /// 进页/长消息：等列表高度稳定后再贴底，避免最新一条只露半截。
  Future<void> _scrollToEndSettled({int attempts = 12}) async {
    var lastMax = -1.0;
    for (var i = 0; i < attempts; i++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!_scroll.hasClients) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
        continue;
      }
      final max = _scroll.position.maxScrollExtent;
      if (max > 0) {
        _scroll.jumpTo(max);
      }
      if (max > 0 && (max - lastMax).abs() < 1.0) {
        // 再补一帧，封面图等异步布局有时会再长一点
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients) return;
        final again = _scroll.position.maxScrollExtent;
        if (again > 0) _scroll.jumpTo(again);
        return;
      }
      lastMax = max;
      await Future<void>.delayed(const Duration(milliseconds: 32));
    }
  }

  Future<void> _openCitation(AgentCitation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemReadingPage(
          itemId: c.itemId,
          openEntry: 'agent',
        ),
      ),
    );
  }

  /// 左侧勾选：在输入区以 chip 展示所选篇目，避免「第二篇」含糊指代。
  void _pickCitationIntoInput(AgentCitation c) {
    if (_sending || _booting) return;
    final title = c.title.trim();
    if (title.isEmpty) return;
    setState(() {
      if (_pickedCitations.containsKey(c.itemId)) {
        _pickedCitations.remove(c.itemId);
      } else {
        _pickedCitations[c.itemId] = c;
      }
    });
    _focus.requestFocus();
  }

  void _openFocusItem() {
    final item = _focusItem;
    if (item == null) return;
    // 从阅读页进来：点卡片回原文
    if (widget.focusItem != null || widget.focusItemId != null) {
      Navigator.of(context).maybePop();
      return;
    }
    unawaited(_openCitation(AgentCitation(
      itemId: item.id,
      title: item.title?.trim().isNotEmpty == true ? item.title! : item.url,
      coverImageUrl: item.coverImageUrl,
      tagNames: [for (final t in item.tags) t.name],
    )));
  }

  Future<void> _clearChat() async {
    if (_sending || _booting || _messages.isEmpty) return;
    final ok = await showAppConfirmDialog(
      context,
      title: '删除聊天记录？',
      message: '当前对话将被清空，无法恢复。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;

    final oldId = _conversationId;
    setState(() {
      _booting = true;
      _error = null;
      _pickedCitations.clear();
    });
    try {
      if (oldId != null) {
        await _repo.archiveConversation(oldId);
      }
      final userId = _cacheUserId;
      if (userId != null) {
        await AgentChatCache.clear(
          userId: userId,
          focusItemId: _focusItemId,
        );
      }
      final conv = await _repo.ensureConversation(
        focusItemId: _focusItemId,
        title: _focusItem?.title,
      );
      if (!mounted) return;
      setState(() {
        _conversationId = conv.id;
        _messages.clear();
        _booting = false;
      });
      unawaited(_persistCache());
      AppToast.show(context, '已删除聊天记录');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _booting = false);
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _booting = false);
      AppToast.show(context, '删除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canClear = !_booting && !_sending && _messages.isNotEmpty;
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: AppSubpageAppBar(
        title: '助手',
        titleTrailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _brandSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            '太子Pro',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _brand,
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '清空聊天',
                onPressed: canClear ? _clearChat : null,
                icon: Icon(
                  Icons.cleaning_services_outlined,
                  size: 20,
                  color: canClear ? _text : const Color(0xFFC5CAD3),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_focusItem != null)
            _FocusItemBanner(
              item: _focusItem!,
              onTap: _openFocusItem,
            ),
          Expanded(
            child: _booting
                ? const Center(child: CircularProgressIndicator())
                : _error != null && _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, style: const TextStyle(color: _muted)),
                            TextButton(
                              onPressed: _bootstrap,
                              child: const Text('重试'),
                            ),
                          ],
                        ),
                      )
                    : _messages.isEmpty
                        ? _EmptyState(focused: _focusItem != null)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
                            itemCount: _messages.length +
                                (_sending && !_streamLive ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_sending &&
                                  !_streamLive &&
                                  index == _messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 2, bottom: 14),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ThinkingIndicator(),
                                  ),
                                );
                              }
                              final m = _messages[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: m.isUser
                                    ? _UserBubble(
                                        text: m.content,
                                        contextMenuBuilder:
                                            _selectionToolbar(),
                                      )
                                    : _AssistantBlock(
                                        text: m.content,
                                        citations: m.citations,
                                        pickedIds: _pickedCitations.keys.toSet(),
                                        onOpen: _openCitation,
                                        onPick: _pickCitationIntoInput,
                                        pickEnabled: !_sending && !_booting,
                                        contextMenuBuilder: _selectionToolbar(
                                          m.citations,
                                        ),
                                      ),
                              );
                            },
                          ),
          ),
          _Composer(
            controller: _input,
            focusNode: _focus,
            enabled: !_sending && !_booting,
            bottomInset: bottom,
            hintText: _focusItemId != null ? '问问这篇…' : null,
            picked: _pickedCitations.values.toList(growable: false),
            onRemovePicked: _pickCitationIntoInput,
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }

  /// 划选工具条：复制纯文本；分享走阅读页摘句海报（先定出处篇）。
  EditableTextContextMenuBuilder _selectionToolbar([
    List<AgentCitation> citations = const [],
  ]) {
    return (context, state) {
      final value = state.textEditingValue;
      final sel = value.selection;
      if (!sel.isValid || sel.isCollapsed) {
        return const SizedBox.shrink();
      }
      final selected = value.text.substring(sel.start, sel.end);
      if (selected.trim().isEmpty) {
        return const SizedBox.shrink();
      }
      final anchors = state.contextMenuAnchors;

      void clearToolbar() {
        ContextMenuController.removeAny();
        state.hideToolbar();
        state.userUpdateTextEditingValue(
          value.copyWith(selection: TextSelection.collapsed(offset: sel.end)),
          SelectionChangedCause.toolbar,
        );
      }

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
          _AgentToolbarAction(
            label: '复制',
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: selected));
              clearToolbar();
              if (mounted) AppToast.show(context, '已复制');
            },
          ),
          _AgentToolbarAction(
            label: '分享',
            onTapWithOrigin: (origin) {
              clearToolbar();
              unawaited(
                _shareQuotePoster(
                  quote: selected,
                  citations: citations,
                  shareOrigin: origin,
                ),
              );
            },
          ),
        ],
      );
    };
  }

  /// 海报需要篇目封面/链接：单篇直接用；多篇先选；阅读锚定优先当前篇。
  Future<void> _shareQuotePoster({
    required String quote,
    required List<AgentCitation> citations,
    Rect? shareOrigin,
  }) async {
    if (!mounted) return;
    final body = quote.trim();
    if (body.isEmpty) return;

    final cite = await _resolveShareCitation(citations);
    if (!mounted) return;
    if (cite == null) {
      AppToast.show(context, '请先选一篇出处再分享海报');
      return;
    }

    try {
      final item = await _itemsRepo.getItem(cite.itemId);
      if (!mounted) return;
      final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
          ? item.canonicalUrl!
          : item.url;
      await shareReadingQuote(
        context: context,
        quote: body,
        title: (item.title ?? cite.title).trim(),
        link: pageUrl,
        coverUrl: item.shareCoverUrl ?? cite.coverImageUrl,
        pageUrl: item.sourcePageUrl,
        sharePositionOrigin: shareOrigin,
        screenSize: MediaQuery.sizeOf(context),
      );
    } catch (error, stack) {
      debugPrint('agent quote share failed: $error\n$stack');
      if (mounted) AppToast.show(context, '分享失败，请稍后重试');
    }
  }

  Future<AgentCitation?> _resolveShareCitation(
    List<AgentCitation> citations,
  ) async {
    final focus = _focusItem;
    if (focus != null) {
      final inCite = citations.where((c) => c.itemId == focus.id).toList();
      if (inCite.isNotEmpty || citations.isEmpty) {
        return AgentCitation(
          itemId: focus.id,
          title: focus.title?.trim().isNotEmpty == true
              ? focus.title!
              : focus.url,
          coverImageUrl: focus.coverImageUrl,
          tagNames: [for (final t in focus.tags) t.name],
        );
      }
    }
    if (citations.length == 1) return citations.first;
    if (citations.length > 1) {
      return showAppBottomSheet<AgentCitation>(
        context: context,
        barrierColor: kAppBottomSheetBarrierColor,
        padding: EdgeInsets.zero,
        includeSafeArea: false,
        isScrollControlled: false,
        builder: (ctx) => _ShareCitationPickerSheet(citations: citations),
      );
    }
    // 无出处时：若输入区已勾选篇目，用勾选的
    if (_pickedCitations.isNotEmpty) {
      final picked = _pickedCitations.values.toList(growable: false);
      if (picked.length == 1) return picked.first;
      return showAppBottomSheet<AgentCitation>(
        context: context,
        barrierColor: kAppBottomSheetBarrierColor,
        padding: EdgeInsets.zero,
        includeSafeArea: false,
        isScrollControlled: false,
        builder: (ctx) => _ShareCitationPickerSheet(citations: picked),
      );
    }
    return null;
  }
}

/// 阅读锚定：顶栏下方固定展示当前篇（与出处同款 ItemListTile）。
class _FocusItemBanner extends StatelessWidget {
  const _FocusItemBanner({
    required this.item,
    required this.onTap,
  });

  final CollectionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
        ? item.canonicalUrl!
        : item.url;
    final subtitle =
        '${platformLabel(item.platform, url: pageUrl)} · ${formatRelativeDay(item.createdAt)}';
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 10, 22, 0),
            child: Text(
              '当前这篇',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF737A85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            child: ItemListTile.fromItem(
              item,
              subtitle: subtitle,
              onTap: onTap,
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE6E8EB)),
        ],
      ),
    );
  }
}

/// 空态：主题色 ✦ 圆标（无光晕）+ 居中标题/副文/能力标。
/// 有锚定篇时顶部已展示条目，这里只留短提示。
class _EmptyState extends StatelessWidget {
  const _EmptyState({this.focused = false});

  final bool focused;

  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE8F0FF);
  static const _title = Color(0xFF1F242E);
  static const _sub = Color(0xFF737A85);

  @override
  Widget build(BuildContext context) {
    if (focused) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(36, 24, 36, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '围绕这篇聊聊',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: _title,
                  height: 1.25,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '问观点、原话，或对照其它收藏。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: _sub,
                  height: 1.55,
                  letterSpacing: 0.15,
                ),
              ),
              SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CapabilityMark(label: '深挖原文'),
                  _CapabilityMark(label: '对照内容'),
                  _CapabilityMark(label: '检索其它'),
                ],
              ),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _brandSoft,
              ),
              alignment: Alignment.center,
              child: const Text(
                '✦',
                style: TextStyle(
                  fontSize: 28,
                  height: 1,
                  color: _brand,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '你的私人助手',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: _title,
                height: 1.25,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '帮你在收藏里更快找到内容，也能深挖原文。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _sub,
                height: 1.55,
                letterSpacing: 0.15,
              ),
            ),
            const SizedBox(height: 22),
            const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _CapabilityMark(label: '检索内容'),
                _CapabilityMark(label: '对照内容'),
                _CapabilityMark(label: '深挖原文'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CapabilityMark extends StatelessWidget {
  const _CapabilityMark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2F6FED).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF2F6FED).withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: Color(0xFF2F6FED),
          height: 1.2,
        ),
      ),
    );
  }
}

/// 助手思考中：浅底胶囊 + 三点呼吸动画。
class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator();

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EBF0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '思考中',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF737A85),
              height: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _Dot(phase: (_ctrl.value + i / 3) % 1.0),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.phase});

  final double phase;

  @override
  Widget build(BuildContext context) {
    // 0→1 内先亮后暗
    final t = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    final opacity = 0.28 + 0.72 * Curves.easeInOut.transform(t);
    final scale = 0.72 + 0.28 * Curves.easeInOut.transform(t);
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFF2F6FED).withValues(alpha: opacity),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}



class _AgentToolbarAction extends StatelessWidget {
  const _AgentToolbarAction({
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

class _ShareCitationPickerSheet extends StatelessWidget {
  const _ShareCitationPickerSheet({required this.citations});

  final List<AgentCitation> citations;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _handle = Color(0xFFD9DBE0);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _handle,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '海报用哪一篇？',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _text,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '分享图需要封面和链接，请选一篇出处',
                style: TextStyle(fontSize: 13, color: _muted, height: 1.35),
              ),
              const SizedBox(height: 12),
              for (final c in citations) ...[
                ItemListTile(
                  title: c.title,
                  subtitle: c.snippet.isNotEmpty ? c.snippet : '用作海报出处',
                  coverUrl: c.coverImageUrl,
                  coverKey: ValueKey('share-pick-${c.itemId}'),
                  tags: [
                    for (var i = 0; i < c.tagNames.length; i++)
                      ItemTagBrief(id: i + 1, name: c.tagNames[i]),
                  ],
                  onTap: () => Navigator.pop(context, c),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.text,
    required this.contextMenuBuilder,
  });

  final String text;
  final EditableTextContextMenuBuilder contextMenuBuilder;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F0FF),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextSelectionTheme(
          data: const TextSelectionThemeData(
            selectionColor: Color(0x662F6FED),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF1F242E),
              height: 1.45,
            ),
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
      ),
    );
  }
}

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.text,
    required this.citations,
    required this.pickedIds,
    required this.onOpen,
    required this.onPick,
    required this.contextMenuBuilder,
    this.pickEnabled = true,
  });

  final String text;
  final List<AgentCitation> citations;
  final Set<int> pickedIds;
  final ValueChanged<AgentCitation> onOpen;
  final ValueChanged<AgentCitation> onPick;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final bool pickEnabled;

  static const _brand = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextSelectionTheme(
          data: const TextSelectionThemeData(
            selectionColor: Color(0x662F6FED),
          ),
          child: AgentMarkdown(
            text,
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
        if (citations.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            '出处',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF737A85),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in citations) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: pickEnabled ? () => onPick(c) : null,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10, top: 8, bottom: 8),
                      child: Icon(
                        pickedIds.contains(c.itemId)
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 24,
                        color: !pickEnabled
                            ? const Color(0xFFD0D5DD)
                            : pickedIds.contains(c.itemId)
                                ? _brand
                                : const Color(0xFFC5CAD3),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ItemListTile(
                    title: c.title,
                    subtitle: c.snippet.isNotEmpty ? c.snippet : '打开阅读',
                    coverUrl: c.coverImageUrl,
                    coverKey: ValueKey('agent-cite-${c.itemId}'),
                    tags: [
                      for (var i = 0; i < c.tagNames.length; i++)
                        ItemTagBrief(id: i + 1, name: c.tagNames[i]),
                    ],
                    onTap: () => onOpen(c),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.bottomInset,
    required this.onSend,
    this.picked = const [],
    this.onRemovePicked,
    this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final double bottomInset;
  final VoidCallback onSend;
  final List<AgentCitation> picked;
  final ValueChanged<AgentCitation>? onRemovePicked;
  final String? hintText;

  static const _brand = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(14, 8, 14, 8 + bottomInset.clamp(0, 28)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE8EBF0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (picked.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 4, 4, 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in picked)
                        _ComposerCitationChip(
                          title: c.title,
                          enabled: enabled,
                          onRemove: onRemovePicked == null
                              ? null
                              : () => onRemovePicked!(c),
                        ),
                    ],
                  ),
                ),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1F242E),
                        height: 1.35,
                      ),
                      decoration: InputDecoration(
                        hintText: picked.isNotEmpty
                            ? '补充想问的…'
                            : (hintText ?? '跟助手说点什么…'),
                        hintStyle: const TextStyle(
                          color: Color(0xFF9AA1AB),
                          fontSize: 16,
                          height: 1.35,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: enabled ? _brand : const Color(0xFFD7E2F5),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: enabled ? onSend : null,
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComposerCitationChip extends StatelessWidget {
  const _ComposerCitationChip({
    required this.title,
    required this.enabled,
    this.onRemove,
  });

  final String title;
  final bool enabled;
  final VoidCallback? onRemove;

  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE8F0FF);

  @override
  Widget build(BuildContext context) {
    final label = title.trim().isEmpty ? '未命名' : title.trim();
    return Material(
      color: _brandSoft,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: enabled ? onRemove : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 168),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _brand,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.close_rounded,
                size: 16,
                color: enabled ? _brand : const Color(0xFFB0B7C3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
