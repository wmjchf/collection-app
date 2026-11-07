import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_chat_cache.dart';
import 'package:super_collection/features/agent/agent_host.dart';
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

/// AI助手（P1：查收藏 + 出处）
///
/// [focusItemId] / [focusItem]：从阅读页带入时展示当前篇，并每轮锚定摘录。
/// [asPanel]：iPad 右侧抽屉内嵌；关闭用「关闭」而非「返回」。
class AgentPage extends StatefulWidget {
  const AgentPage({
    super.key,
    this.focusItemId,
    this.focusItem,
    this.asPanel = false,
  });

  final int? focusItemId;
  final CollectionItem? focusItem;
  final bool asPanel;

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
  /// 确认改标签进行中
  bool _confirmingAction = false;
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

  Future<void> _confirmPendingAction(AgentMessage message, bool approve) async {
    final convId = _conversationId;
    if (convId == null ||
        _confirmingAction ||
        _sending ||
        message.pendingAction?.isPending != true) {
      return;
    }
    setState(() => _confirmingAction = true);
    try {
      final result = await _repo.confirmAction(
        conversationId: convId,
        messageId: message.id,
        approve: approve,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == message.id);
        if (idx >= 0) {
          final settled = result.pendingAction ??
              message.pendingAction?.copyWith(
                status: approve ? 'approved' : 'cancelled',
              );
          _messages[idx] = message.copyWith(
            pendingAction: settled,
            clearPendingAction: settled == null,
          );
        }
        final next = result.assistantMessage;
        if (next != null && !_messages.any((m) => m.id == next.id)) {
          _messages.add(next);
        }
        _confirmingAction = false;
      });
      unawaited(_persistCache());
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _confirmingAction = false);
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _confirmingAction = false);
      AppToast.show(context, '操作失败，请重试');
    }
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

  void _closePanel() {
    final host = AgentHost.maybeOf(context);
    if (host != null) {
      host.closePanel();
      return;
    }
    Navigator.of(context).maybePop();
  }

  PreferredSizeWidget _buildAppBar({required bool canClear}) {
    final proBadge = Container(
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
    );
    final clearBtn = IconButton(
      tooltip: '清空聊天',
      onPressed: canClear ? _clearChat : null,
      icon: Icon(
        Icons.cleaning_services_outlined,
        size: 20,
        color: canClear ? _text : const Color(0xFFC5CAD3),
      ),
    );

    if (widget.asPanel) {
      return AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: 84,
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: TextButton(
            onPressed: _closePanel,
            style: TextButton.styleFrom(
              foregroundColor: _text,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '关闭',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w400),
            ),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'AI助手',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(width: 8),
            proBadge,
          ],
        ),
        actions: [clearBtn],
      );
    }

    return AppSubpageAppBar(
      title: 'AI助手',
      titleTrailing: proBadge,
      actions: [
        SizedBox(
          width: 88,
          child: Align(
            alignment: Alignment.centerRight,
            child: clearBtn,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final canClear = !_booting && !_sending && _messages.isNotEmpty;
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(canClear: canClear),
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
                                        pendingAction: m.pendingAction,
                                        showCopyAll: m.isComposeArticleDraft,
                                        pickedIds: _pickedCitations.keys.toSet(),
                                        onOpen: _openCitation,
                                        onPick: _pickCitationIntoInput,
                                        pickEnabled: !_sending && !_booting,
                                        confirmEnabled:
                                            !_sending &&
                                            !_booting &&
                                            !_confirmingAction,
                                        onConfirmAction: m.pendingAction
                                                    ?.isPending ==
                                                true
                                            ? (approve) =>
                                                _confirmPendingAction(
                                                  m,
                                                  approve,
                                                )
                                            : null,
                                        contextMenuBuilder: _selectionToolbar(
                                          m.citations,
                                        ),
                                      ),
                              );
                            },
                          ),
          ),
          if (!_booting && !_sending)
            _AgentPresets(
              items: _resolvePresetItems(),
              enabled: true,
              onDraft: (text) {
                final draft =
                    text.endsWith('…') ? text.substring(0, text.length - 1) : text;
                _input
                  ..text = draft
                  ..selection =
                      TextSelection.collapsed(offset: draft.length);
                _focus.requestFocus();
              },
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

  /// 空会话起步；有回复后按上一轮规则切换（不走 AI）。
  List<String> _resolvePresetItems() {
    if (_messages.isEmpty) {
      return _AgentPresetRules.starters(focused: _focusItem != null);
    }
    AgentMessage? lastAssistant;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isAssistant) {
        lastAssistant = _messages[i];
        break;
      }
    }
    if (lastAssistant == null) {
      return _AgentPresetRules.starters(focused: _focusItem != null);
    }
    return _AgentPresetRules.fromAssistant(
      lastAssistant,
      focused: _focusItem != null,
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
        watermark: false,
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

/// 空态：主题色 ✦ 圆标（无光晕）+ 居中标题/副文。
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
              '你的AI助手',
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
              '意图搜索、对照、深挖；也可改标签与归类。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: _sub,
                height: 1.55,
                letterSpacing: 0.15,
              ),
            ),
          ],
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

  static const _brand = Color(0xFF2F6FED);
  static const _body = Color(0xFF1F242E);
  static final _titleRef = RegExp(r'「([^」]*)」');

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(
      fontSize: 16,
      color: _body,
      height: 1.45,
    );
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
          child: SelectableText.rich(
            TextSpan(style: base, children: _spans(text, base)),
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
      ),
    );
  }

  /// 「标题」用图标 + 主题色加粗，和后面问句区分开。
  static List<InlineSpan> _spans(String text, TextStyle base) {
    final matches = _titleRef.allMatches(text).toList(growable: false);
    if (matches.isEmpty) {
      return [TextSpan(text: text, style: base)];
    }
    final titleStyle = base.copyWith(
      color: _brand,
      fontWeight: FontWeight.w600,
      height: 1.4,
      fontSize: 15,
    );
    final out = <InlineSpan>[];
    var start = 0;
    for (final m in matches) {
      if (m.start > start) {
        out.add(TextSpan(text: text.substring(start, m.start), style: base));
      }
      final title = (m.group(1) ?? '').trim();
      if (title.isEmpty) {
        out.add(TextSpan(text: m.group(0), style: base));
      } else {
        out.add(
          TextSpan(
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(
                    Icons.article_outlined,
                    size: 15,
                    color: _brand,
                  ),
                ),
              ),
              TextSpan(
                text: '「',
                style: titleStyle.copyWith(fontWeight: FontWeight.w500),
              ),
              TextSpan(text: title, style: titleStyle),
              TextSpan(
                text: '」',
                style: titleStyle.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        );
      }
      start = m.end;
    }
    if (start < text.length) {
      out.add(TextSpan(text: text.substring(start), style: base));
    }
    return out;
  }
}

/// 转写写文章草稿：文末固定说明行，复制时剥离。
final _composeArticleFooterRe = RegExp(
  r'\n+---\n已按转写整理成文章语体[^\n]*\s*$',
);

String _composeArticleCopyBody(String text) =>
    text.replaceFirst(_composeArticleFooterRe, '').trim();

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    required this.text,
    required this.citations,
    required this.pickedIds,
    required this.onOpen,
    required this.onPick,
    required this.contextMenuBuilder,
    this.pendingAction,
    this.showCopyAll = false,
    this.pickEnabled = true,
    this.confirmEnabled = true,
    this.onConfirmAction,
  });

  final String text;
  final List<AgentCitation> citations;
  final AgentPendingAction? pendingAction;
  final bool showCopyAll;
  final Set<int> pickedIds;
  final ValueChanged<AgentCitation> onOpen;
  final ValueChanged<AgentCitation> onPick;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final bool pickEnabled;
  final bool confirmEnabled;
  final ValueChanged<bool>? onConfirmAction;

  static const _brand = Color(0xFF2F6FED);

  Future<void> _copyAll(BuildContext context) async {
    final body = _composeArticleCopyBody(text);
    if (body.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) AppToast.show(context, '已复制');
  }

  @override
  Widget build(BuildContext context) {
    final showConfirm = pendingAction?.isPending == true && onConfirmAction != null;
    // 长文/标题文/写文章草稿都给复制；不依赖文末标记（避免 plan 未走 compose 时无按钮）
    final trimmed = text.trim();
    final copyVisible = showCopyAll ||
        trimmed.contains('已按转写整理成文章语体') ||
        trimmed.startsWith('# ') ||
        trimmed.length >= 160;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (copyVisible) ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _copyAll(context),
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text(
                '复制全文',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _brand,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextSelectionTheme(
          data: const TextSelectionThemeData(
            selectionColor: Color(0x662F6FED),
          ),
          child: AgentMarkdown(
            text,
            contextMenuBuilder: contextMenuBuilder,
          ),
        ),
        if (copyVisible) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _copyAll(context),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text(
                '复制全文',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: _brand,
                side: const BorderSide(color: Color(0xFFB7C9F5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
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
        if (showConfirm) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    confirmEnabled ? () => onConfirmAction!(false) : null,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF737A85),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '取消',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed:
                    confirmEnabled ? () => onConfirmAction!(true) : null,
                style: TextButton.styleFrom(
                  foregroundColor: _brand,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  pendingAction?.confirmLabel ?? '确认调整',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 按上一轮助手回复用规则推断预设（不走模型）。
/// 挂确认条的最后一步不展示预设，避免与「确认整理」抢决策。
class _AgentPresetRules {
  static List<String> starters({required bool focused}) {
    if (focused) {
      return const [
        '这篇的核心观点是什么？',
        '根据转写写一篇文章',
        '还有哪些相关收藏？',
        '调整这篇的标签',
      ];
    }
    return const [
      '最近收藏了哪些内容？',
      '现在有哪些标签？',
      '整理归类',
      '查找关于…',
    ];
  }

  static List<String> fromAssistant(
    AgentMessage message, {
    required bool focused,
  }) {
    // 确认写入步骤：只用消息上的确认/取消，不再挂预设
    if (message.pendingAction?.isPending == true) {
      return const [];
    }

    final content = message.content;
    if (_looksLikeOrganizeAsk(content)) {
      return const [
        '按行业归类',
        '按主题归类',
        '由你来分',
        '我有自己的分法…',
      ];
    }
    if (_looksLikeTagInventory(content)) {
      final title = _firstBookTitle(content);
      return [
        '整理归类',
        '还有哪些？',
        if (title != null) '调整《$title》的标签',
        '查找关于…',
      ];
    }
    if (message.citations.isNotEmpty) {
      final title = message.citations.first.title.trim();
      final short = title.length > 12 ? '${title.substring(0, 12)}…' : title;
      return [
        if (short.isNotEmpty) '深入解读《$short》',
        '对照这几篇',
        '还有其它吗？',
        '整理归类',
      ];
    }
    if (focused) {
      return const [
        '再展开说明',
        '根据转写写一篇文章',
        '对照其它收藏',
        '调整这篇的标签',
      ];
    }
    return const [
      '还有其它吗？',
      '整理归类',
      '现在有哪些标签？',
      '查找关于…',
    ];
  }

  static bool _looksLikeOrganizeAsk(String content) {
    return content.contains('可以先听听你的分类意见') ||
        content.contains('你更希望怎么分');
  }

  /// 仅认 list_tags 口吻；避免「按主题或标签筛选」+《标题》误判。
  static bool _looksLikeTagInventory(String content) {
    if (RegExp(r'现在共\s*\d+\s*个标签').hasMatch(content)) return true;
    if (content.contains('有标签的文章')) return true;
    if (content.contains('没有文章') &&
        RegExp(r'\*\*[^*]{1,40}\*\*：').hasMatch(content)) {
      return true;
    }
    return false;
  }

  static String? _firstBookTitle(String content) {
    final m = RegExp(r'《([^》]+)》').firstMatch(content);
    final t = m?.group(1)?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length > 16 ? '${t.substring(0, 16)}…' : t;
  }
}

/// 输入框上方口语预设：点选先填入输入框，由用户再发。
class _AgentPresets extends StatelessWidget {
  const _AgentPresets({
    required this.items,
    required this.enabled,
    required this.onDraft,
  });

  final List<String> items;
  final bool enabled;
  final ValueChanged<String> onDraft;

  static const _brand = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        child: SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final text = items[index];
              return Material(
                color: _brand.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: enabled ? () => onDraft(text) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _brand.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                        color: enabled ? _brand : _brand.withValues(alpha: 0.4),
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (picked.isNotEmpty) ...[
                      SizedBox(
                        height: 28,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(2, 2, 4, 0),
                          itemCount: picked.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 6),
                          itemBuilder: (context, index) {
                            final c = picked[index];
                            return _ComposerCitationChip(
                              title: c.title,
                              enabled: enabled,
                              onRemove: onRemovePicked == null
                                  ? null
                                  : () => onRemovePicked!(c),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    TextField(
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
                  ],
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onRemove : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 148),
          padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _brand.withValues(alpha: 0.16)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.article_outlined, size: 14, color: _brand),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _brand,
                    height: 1.15,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              Icon(
                Icons.close_rounded,
                size: 14,
                color: enabled ? _brand : const Color(0xFFB0B7C3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
