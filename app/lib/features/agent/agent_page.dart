import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_collection/core/analytics/analytics.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_bottom_sheet.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_chat_cache.dart';
import 'package:super_collection/features/agent/agent_host.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/agent/agent_models.dart';
import 'package:super_collection/features/agent/agent_preset_cache.dart';
import 'package:super_collection/features/agent/agent_repository.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/home/home_format.dart';
import 'package:super_collection/features/items/cover_image.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/items/items_repository.dart';
import 'package:super_collection/features/items/reading_quote_share.dart';
import 'package:super_collection/features/items/item_transcript_refresh.dart';
import 'package:super_collection/features/items/transcript_models.dart';
import 'package:super_collection/features/items/transcript_picker_sheet.dart';
import 'package:super_collection/features/items/transcript_segment_panel.dart';
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
  /// 已有流式 token 时隐藏「思考中」占位
  bool _streamLive = false;
  /// 流式任务规划独白
  String _liveThinking = '';
  /// 规划已结束、正文未出（用于「思考完成 + loading」）
  bool _planDone = false;
  String? _error;
  CollectionItem? _focusItem;
  /// 已勾选进输入区的出处（以 chip 展示，发送时拼进正文）
  final Map<int, AgentCitation> _pickedCitations = {};
  /// 每条助手消息已露出的出处条数（默认 [_citationPageSize]，点加载更多再加）
  final Map<int, int> _citationRevealByMsgId = {};
  static const int _citationPageSize = 3;
  int? _cacheUserId;
  /// 动态预设（LLM）；为空则用规则兜底
  List<String>? _llmPresets;
  String? _presetCacheKey;
  int _presetFetchGen = 0;
  /// 助手内转写轮询世代；dispose / 新任务时递增以取消旧轮询
  int _transcriptPollGen = 0;
  /// 已准备过气泡确认文案的助手消息 id
  final Set<int> _transcriptConfirmStarted = {};
  /// 仅当次在气泡点过「开始生成」才允许文稿成功后自动成文（进页续跑不成文）
  bool _allowResumeComposeAfterTranscript = false;

  int? get _focusItemId =>
      widget.focusItemId ?? widget.focusItem?.id ?? _focusItem?.id;

  int _citationRevealCount(int messageId) {
    final n = _citationRevealByMsgId[messageId];
    if (n == null || n < _citationPageSize) return _citationPageSize;
    return n;
  }

  void _loadMoreCitations(int messageId, int totalVisible) {
    if (totalVisible <= _citationPageSize) return;
    setState(() {
      final cur = _citationRevealCount(messageId);
      final next = cur + _citationPageSize;
      _citationRevealByMsgId[messageId] =
          next > totalVisible ? totalVisible : next;
    });
  }

  @override
  void initState() {
    super.initState();
    _focusItem = widget.focusItem;
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _transcriptPollGen++;
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
      presets: _llmPresets,
      presetKey: _presetCacheKey,
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
          // 与会话一并恢复预设，避免杀进程后回落规则/重打模型
          if (cached.presets.isNotEmpty) {
            _llmPresets = cached.presets;
            _presetCacheKey = cached.presetKey;
          }
          _booting = false;
          _error = null;
        });
        showedCache = true;
        if (_messages.isNotEmpty) {
          unawaited(_scrollToEndSettled());
        }
        unawaited(_refreshLlmPresets());
        unawaited(_resumeActiveTranscriptJob());
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
      unawaited(_refreshLlmPresets());
      unawaited(_resumeActiveTranscriptJob());
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
      _liveThinking = '';
      _planDone = false;
      _pickedCitations.clear();
      _llmPresets = null;
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
        onPhase: (phase) {
          if (!mounted) return;
          // planning 之后进入 searching/answering = 规划结束
          if (phase == 'searching' || phase == 'answering') {
            setState(() => _planDone = true);
          }
        },
        onUser: (user) {
          if (!mounted) return;
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.id == optimisticUser.id);
            if (idx >= 0) _messages[idx] = user;
          });
        },
        onThinking: (delta, {text}) {
          if (!mounted) return;
          setState(() {
            if (text != null && text.isNotEmpty) {
              _liveThinking = text;
            } else {
              _liveThinking += delta;
            }
            // 思考开始时先挂助手占位，便于展示规划区
            final aIdx =
                _messages.indexWhere((m) => m.id == streamAssistantId);
            if (aIdx < 0 && _liveThinking.isNotEmpty) {
              _messages.add(
                AgentMessage(
                  id: streamAssistantId,
                  role: 'assistant',
                  content: '',
                  thinking: _liveThinking,
                ),
              );
            } else if (aIdx >= 0) {
              _messages[aIdx] = _messages[aIdx].copyWith(
                thinking: _liveThinking,
              );
            }
          });
          _scrollToEnd();
        },
        onToken: (delta) {
          if (!mounted) return;
          setState(() {
            if (!_streamLive) {
              _streamLive = true;
              final aIdx =
                  _messages.indexWhere((m) => m.id == streamAssistantId);
              if (aIdx >= 0) {
                _messages[aIdx] = _messages[aIdx].copyWith(
                  content: _messages[aIdx].content + delta,
                  thinking: _liveThinking.isNotEmpty
                      ? _liveThinking
                      : _messages[aIdx].thinking,
                );
              } else {
                _messages.add(
                  AgentMessage(
                    id: streamAssistantId,
                    role: 'assistant',
                    content: delta,
                    thinking: _liveThinking,
                  ),
                );
              }
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
        _liveThinking = '';
        _planDone = false;
      });
      unawaited(_persistCache());
      _scrollToEnd();
      unawaited(_refreshLlmPresets());
      unawaited(_maybeHandleStartTranscript(result.assistantMessage));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere(
          (m) => m.id == optimisticUser.id || m.id == streamAssistantId,
        );
        _sending = false;
        _streamLive = false;
        _liveThinking = '';
        _planDone = false;
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
        _liveThinking = '';
        _planDone = false;
      });
      AppToast.show(context, '发送失败，请重试');
    }
  }

  AgentMessage? _lastStartTranscriptMessage() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.isAssistant && m.pendingAction?.isTranscriptJobActive == true) {
        return m;
      }
    }
    return null;
  }

  Future<void> _resumeActiveTranscriptJob() async {
    final msg = _lastStartTranscriptMessage();
    if (msg == null) return;
    final pa = msg.pendingAction!;
    if (pa.status == 'running') {
      unawaited(_pollAgentTranscript(msg.id));
      return;
    }
    if (pa.status == 'pending') {
      final itemId = pa.itemId > 0 ? pa.itemId : (_focusItemId ?? 0);
      if (itemId <= 0) return;
      try {
        final st = await _itemsRepo.getTranscriptStatus(itemId);
        if (!mounted) return;
        if (st.hasPending) {
          // 服务端任务仍在跑：跳过确认直接续轮询
          _patchAssistantMessage(
            msg.id,
            pending: pa.copyWith(
              status: 'running',
              segmentKey: st.pendingSegmentKey ?? pa.segmentKey,
            ),
          );
          unawaited(_pollAgentTranscript(msg.id));
          return;
        }
        final item = await _itemsRepo.getItem(itemId);
        if (!mounted) return;
        if (_focusItem?.id == itemId) {
          setState(() => _focusItem = item);
        }
        final done = item.transcriptSegments.values
            .any((s) => s.isSuccess && s.hasText);
        if (done) {
          // 离开期间已转写完：只结算成功态，不再自动成文（避免每次进页重发）
          _patchAssistantMessage(
            msg.id,
            content: '文稿已生成。可以说「整理成一篇文章」，或到阅读页查看全文。',
            pending: pa.copyWith(status: 'success', clearPhase: true),
          );
          ItemTranscriptRefresh.notify(itemId);
          unawaited(_refreshLlmPresets());
          return;
        }
      } catch (_) {
        // 拉状态失败则走确认流程
      }
      unawaited(_maybeHandleStartTranscript(msg));
    }
  }

  Future<void> _maybeHandleStartTranscript(AgentMessage assistant) async {
    final pa = assistant.pendingAction;
    if (pa == null || !pa.isStartTranscript) return;
    if (pa.status == 'running') {
      unawaited(_pollAgentTranscript(assistant.id));
      return;
    }
    if (pa.status != 'pending') return;
    // 只准备气泡内确认文案，不弹系统框；用户点「开始生成」再提交
    await _prepareTranscriptConfirm(assistant);
  }

  /// 文稿确认：文案已由后端随 pendingAction 写好；此处只做档位门控。
  Future<void> _prepareTranscriptConfirm(AgentMessage message) async {
    final pa = message.pendingAction;
    if (pa == null || !pa.isTranscriptConfirmPending) return;
    if (_transcriptConfirmStarted.contains(message.id)) return;
    _transcriptConfirmStarted.add(message.id);

    final allowed = await ensurePlanFeatures(
      context,
      requirements: [
        (has: (f) => f.transcript, tier: UsagePlan.prince),
      ],
    );
    if (!allowed || !mounted) {
      _patchAssistantMessage(
        message.id,
        content: '生成文稿需要太子Pro。开通后可再说「生成文稿」。',
        pending: pa.copyWith(status: 'cancelled'),
      );
    }
  }

  void _patchAssistantMessage(
    int messageId, {
    String? content,
    AgentPendingAction? pending,
  }) {
    if (!mounted) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final nextContent = content ?? _messages[idx].content;
    setState(() {
      _messages[idx] = _messages[idx].copyWith(
        content: content,
        pendingAction: pending,
      );
    });
    unawaited(_persistCache());
    final st = pending?.status;
    if (pending != null &&
        pending.isStartTranscript &&
        messageId > 0 &&
        (st == 'success' || st == 'failed' || st == 'cancelled')) {
      unawaited(_settleTranscriptOnServer(
        messageId: messageId,
        status: st!,
        content: nextContent,
      ));
    }
  }

  Future<void> _settleTranscriptOnServer({
    required int messageId,
    required String status,
    String? content,
  }) async {
    final convId = _conversationId;
    if (convId == null || messageId <= 0) return;
    try {
      await _repo.settleTranscriptAction(
        conversationId: convId,
        messageId: messageId,
        status: status,
        content: content,
      );
    } catch (_) {
      // 结算失败不挡本轮 UI；下次进页仍可能再结算一次（幂等）
    }
  }

  Future<void> _beginAgentTranscript(AgentMessage message) async {
    final pa = message.pendingAction;
    if (pa == null || !pa.isStartTranscript) return;
    if (pa.status != 'pending') return;
    final itemId = pa.itemId > 0 ? pa.itemId : (_focusItemId ?? 0);
    if (itemId <= 0) {
      _patchAssistantMessage(
        message.id,
        content: '生成文稿失败：缺少当前篇目。请从阅读页打开助手后再试。',
        pending: pa.copyWith(status: 'failed'),
      );
      return;
    }

    List<TranscriptTarget> targets;
    try {
      targets = await _itemsRepo.getTranscriptTargets(itemId);
    } on ApiException catch (e) {
      if (!mounted) return;
      await handleApiException(context, e);
      _patchAssistantMessage(
        message.id,
        content: '生成文稿失败：${e.message}',
        pending: pa.copyWith(status: 'failed'),
      );
      return;
    } catch (_) {
      if (!mounted) return;
      _patchAssistantMessage(
        message.id,
        content: '生成文稿失败：无法获取可用的音视频。',
        pending: pa.copyWith(status: 'failed'),
      );
      return;
    }

    final pendingTargets =
        targets.where((t) => t.status != 'success').toList(growable: false);
    if (pendingTargets.isEmpty) {
      _patchAssistantMessage(
        message.id,
        content: '这篇已经有文稿了。可以说「整理成一篇文章」。',
        pending: pa.copyWith(status: 'success'),
      );
      ItemTranscriptRefresh.notify(itemId);
      if (pa.resumeCompose && _allowResumeComposeAfterTranscript) {
        _allowResumeComposeAfterTranscript = false;
        unawaited(_send('整理成一篇文章'));
      } else {
        _allowResumeComposeAfterTranscript = false;
      }
      return;
    }

    TranscriptTarget? chosen;
    if (pendingTargets.length == 1) {
      chosen = pendingTargets.first;
    } else {
      if (!mounted) return;
      chosen = await showTranscriptPickerSheet(
        context,
        targets: pendingTargets,
      );
    }
    if (!mounted) return;
    if (chosen == null) {
      _patchAssistantMessage(
        message.id,
        content: '已取消。需要时再说「生成文稿」。',
        pending: pa.copyWith(status: 'cancelled'),
      );
      unawaited(_refreshLlmPresets());
      return;
    }

    String? mediaUrl;
    if (chosen.needsClientResolve) {
      try {
        final refreshed = await _itemsRepo.refreshVideo(itemId);
        if (!mounted) return;
        setState(() {
          if (_focusItem?.id == itemId) _focusItem = refreshed;
        });
        mediaUrl = refreshed.videoUrl;
        if (mediaUrl == null || mediaUrl.trim().isEmpty) {
          _patchAssistantMessage(
            message.id,
            content: '无法获取音视频直链，请先到阅读页播放或刷新视频后再生成文稿。',
            pending: pa.copyWith(status: 'failed'),
          );
          return;
        }
      } on ApiException catch (e) {
        if (!mounted) return;
        await handleApiException(context, e);
        _patchAssistantMessage(
          message.id,
          content: '无法获取音视频直链：${e.message}',
          pending: pa.copyWith(status: 'failed'),
        );
        return;
      } catch (_) {
        if (!mounted) return;
        _patchAssistantMessage(
          message.id,
          content: '无法获取音视频直链，请先到阅读页播放或刷新视频后再生成文稿。',
          pending: pa.copyWith(status: 'failed'),
        );
        return;
      }
    }

    try {
      final updated = await _itemsRepo.requestTranscript(
        itemId,
        segmentKey: chosen.segmentKey,
        mediaUrl: mediaUrl,
      );
      if (!mounted) return;
      Analytics.instance.transcriptRequest(
        itemId: itemId,
        segmentKey: chosen.segmentKey,
      );
      if (_focusItem?.id == itemId) {
        setState(() => _focusItem = updated);
      }
      _patchAssistantMessage(
        message.id,
        content: pa.resumeCompose
            ? '正在生成文稿，完成后会自动整理成文章。'
            : '正在生成文稿，请稍候。',
        pending: pa.copyWith(
          status: 'running',
          segmentKey: chosen.segmentKey,
          phase: 'queued',
          phaseLabel: '排队等待中',
          phaseHint: '即将开始准备音视频并提交识别',
          phaseAt: DateTime.now(),
        ),
      );
      unawaited(_pollAgentTranscript(message.id));
    } on ApiException catch (e) {
      if (!mounted) return;
      await handleApiException(context, e);
      _patchAssistantMessage(
        message.id,
        content: '生成文稿失败：${e.message}',
        pending: pa.copyWith(status: 'failed'),
      );
    } catch (_) {
      if (!mounted) return;
      _patchAssistantMessage(
        message.id,
        content: '生成文稿失败，请稍后重试。',
        pending: pa.copyWith(status: 'failed'),
      );
    }
  }

  Future<void> _pollAgentTranscript(int messageId) async {
    final gen = ++_transcriptPollGen;
    for (var i = 0; i < 90; i++) {
      if (i > 0) {
        await Future<void>.delayed(const Duration(seconds: 4));
      }
      if (!mounted || gen != _transcriptPollGen) return;

      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx < 0) return;
      final msg = _messages[idx];
      final pa = msg.pendingAction;
      if (pa == null || !pa.isStartTranscript) return;
      final itemId = pa.itemId > 0 ? pa.itemId : (_focusItemId ?? 0);
      if (itemId <= 0) return;

      try {
        final st = await _itemsRepo.getTranscriptStatus(itemId);
        if (!mounted || gen != _transcriptPollGen) return;

        if (st.hasPending) {
          final key = st.pendingSegmentKey ?? pa.segmentKey;
          final seg = key != null ? st.segments[key] : null;
          TranscriptSegment? active = seg;
          if (active == null) {
            for (final s in st.segments.values) {
              if (s.isPending) {
                active = s;
                break;
              }
            }
          }
          _patchAssistantMessage(
            messageId,
            pending: pa.copyWith(
              status: 'running',
              segmentKey: key ?? pa.segmentKey,
              phase: active?.phase ?? pa.phase,
              phaseLabel: active?.phaseLabel ?? pa.phaseLabel,
              phaseHint: active?.phaseHint ?? pa.phaseHint,
              phaseAt: active?.phaseAt ?? pa.phaseAt,
            ),
          );
          continue;
        }

        final item = await _itemsRepo.getItem(itemId);
        if (!mounted || gen != _transcriptPollGen) return;
        if (_focusItem?.id == itemId) {
          setState(() => _focusItem = item);
        }

        final anySuccess = st.segments.values.any((s) => s.isSuccess);
        if (anySuccess) {
          final shouldCompose =
              pa.resumeCompose && _allowResumeComposeAfterTranscript;
          _allowResumeComposeAfterTranscript = false;
          _patchAssistantMessage(
            messageId,
            content: shouldCompose
                ? '文稿已生成，正在整理成文章…'
                : '文稿已生成。可以说「整理成一篇文章」，或到阅读页查看全文。',
            pending: pa.copyWith(status: 'success', clearPhase: true),
          );
          ItemTranscriptRefresh.notify(itemId);
          unawaited(_refreshLlmPresets());
          if (shouldCompose) {
            unawaited(_send('整理成一篇文章'));
          }
          return;
        }

        String? errMsg;
        for (final s in st.segments.values) {
          final e = s.error?.trim();
          if (e != null && e.isNotEmpty) {
            errMsg = e;
            break;
          }
        }
        _patchAssistantMessage(
          messageId,
          content: '生成文稿失败：${errMsg ?? '请稍后重试'}',
          pending: pa.copyWith(status: 'failed', clearPhase: true),
        );
        unawaited(_refreshLlmPresets());
        return;
      } catch (_) {
        // ignore poll errors
      }
    }

    if (!mounted || gen != _transcriptPollGen) return;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    final pa = _messages[idx].pendingAction;
    if (pa == null || !pa.isTranscriptJobActive) return;
    _patchAssistantMessage(
      messageId,
      content: '生成文稿等待超时，请稍后在助手里再说「生成文稿」。',
      pending: pa.copyWith(status: 'failed', clearPhase: true),
    );
  }

  bool _hasSuccessfulTranscript() {
    final item = _focusItem;
    if (item == null) return false;
    return item.transcriptSegments.values.any((s) => s.isSuccess && s.hasText);
  }

  /// 与后端 isVideoItem 对齐：图集/文章不算；顶栏视频才算。
  bool _focusIsVideo() {
    final item = _focusItem;
    if (item == null) return false;
    if (item.isImageGallery) return false;
    return item.hasVideo;
  }

  bool _focusIsGallery() => _focusItem?.isImageGallery == true;

  bool _focusCanComposeVideo() =>
      _focusIsVideo() && _hasSuccessfulTranscript();

  /// 与后端 looksLikeKnowledgeGallery 对齐：生活向图集不推成文预设。
  bool _focusLooksLikeKnowledgeGallery() {
    final item = _focusItem;
    if (item == null) return false;
    final text = [
      item.title ?? '',
      item.summary ?? '',
      item.content ?? '',
    ].join('\n');
    final stripped = text
        .replaceAll(RegExp(r'#[^\s#]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final lifestyle = RegExp(
      r'穿搭|ootd|oootd|自拍|妆造|美甲|探店|打卡|风景|旅游|旅行|出片|拍照|写真|咖啡馆|咖啡店|氛围感|好物分享|种草|瘦身|减肥|护肤|发型',
      caseSensitive: false,
    ).hasMatch(text);
    final knowledge = RegExp(
      r'教程|笔记|学习|课件|讲义|原理|步骤|方法论|知识点|干货|总结|框架|流程图|白皮书|指南|入门|导论|概念|公式|算法|模型|llm|gpt|agent|skill|提示词|prompt|复盘|清单|checklist|how\s*to|手册',
      caseSensitive: false,
    ).hasMatch(text);
    if (knowledge) return true;
    if (lifestyle) return false;
    return stripped.length >= 120;
  }

  bool _focusCanComposeGallery() =>
      _focusIsGallery() && _focusLooksLikeKnowledgeGallery();

  /// 异步拉动态预设。不计用户额度（服务端约定）。
  /// 全局空会话不请求；单篇或已有对话才拉。键未变则复用（含会话缓存里恢复的）。
  Future<void> _refreshLlmPresets() async {
    final convId = _conversationId;
    final userId = _cacheUserId;
    if (convId == null || userId == null || !mounted) return;
    final focused = _focusItem != null || _focusItemId != null;
    final hasMessages = _messages.isNotEmpty;
    if (!focused && !hasMessages) {
      if (mounted) {
        setState(() {
          _llmPresets = null;
          _presetCacheKey = null;
        });
      }
      return;
    }
    AgentMessage? lastAssistant;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].isAssistant) {
        lastAssistant = _messages[i];
        break;
      }
    }
    final pendingBusy = lastAssistant?.pendingAction?.isPending == true ||
        lastAssistant?.pendingAction?.isTranscriptJobActive == true;
    if (pendingBusy) {
      if (mounted) {
        setState(() {
          _llmPresets = const [];
          _presetCacheKey = null;
        });
      }
      return;
    }

    final cacheKey = AgentPresetCache.cacheKey(
      userId: userId,
      focusItemId: _focusItemId,
      conversationId: convId,
      lastAssistantId: lastAssistant?.id ?? 0,
      hasSuccessfulTranscript: _hasSuccessfulTranscript(),
    );
    // 已与当前键一致（含刚从会话缓存恢复）→ 不调模型
    if (_presetCacheKey == cacheKey &&
        _llmPresets != null &&
        _llmPresets!.isNotEmpty) {
      return;
    }

    final gen = ++_presetFetchGen;
    try {
      final list = await _repo.fetchPresets(
        conversationId: convId,
        focusItemId: _focusItemId,
        lastAssistantContent: lastAssistant?.content,
        hasPendingAction: lastAssistant?.pendingAction?.isPending == true ||
            lastAssistant?.pendingAction?.isTranscriptJobActive == true,
      );
      if (!mounted || gen != _presetFetchGen) return;
      setState(() {
        _llmPresets = list;
        _presetCacheKey = cacheKey;
      });
      unawaited(_persistCache());
    } catch (_) {
      if (!mounted || gen != _presetFetchGen) return;
      // 已有恢复的预设则保留，避免杀进程后闪没
      if (_llmPresets != null && _llmPresets!.isNotEmpty) return;
      setState(() {
        _llmPresets = const [];
        _presetCacheKey = null;
      });
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

  void _openInventoryTag(AgentTagChip tag) {
    final tagsRepo = TagsRepository();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: tag.name,
          tagId: tag.isSystem ? null : tag.id,
          loader: ({required limit, required offset}) => tagsRepo.listTagItems(
            tag.id,
            limit: limit,
            offset: offset,
          ),
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
    final pa = message.pendingAction;
    if (convId == null ||
        _confirmingAction ||
        _sending ||
        pa?.isPending != true) {
      return;
    }

    // 转写：气泡内确认，本地提交，不走改标 confirm API
    if (pa!.isTranscriptConfirmPending) {
      if (!approve) {
        _allowResumeComposeAfterTranscript = false;
        _patchAssistantMessage(
          message.id,
          content: pa.resumeCompose
              ? '已取消。需要时再说「整理成一篇文章」或「生成文稿」。'
              : '已取消。需要时再说「生成文稿」。',
          pending: pa.copyWith(status: 'cancelled'),
        );
        unawaited(_refreshLlmPresets());
        return;
      }
      _allowResumeComposeAfterTranscript = pa.resumeCompose;
      setState(() => _confirmingAction = true);
      try {
        await _beginAgentTranscript(message);
      } finally {
        if (mounted) setState(() => _confirmingAction = false);
      }
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
        _llmPresets = null;
      });
      unawaited(_persistCache());
      _scrollToEnd();
      unawaited(_refreshLlmPresets());
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
      pageUrl: item.sourcePageUrl,
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
        _llmPresets = null;
        _booting = false;
      });
      unawaited(_persistCache());
      AppToast.show(context, '已删除聊天记录');
      unawaited(_refreshLlmPresets());
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
                                (_sending &&
                                        !_streamLive &&
                                        _liveThinking.trim().isEmpty
                                    ? 1
                                    : 0),
                            itemBuilder: (context, index) {
                              if (_sending &&
                                  !_streamLive &&
                                  _liveThinking.trim().isEmpty &&
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
                              final thinkingText = m.displayThinking.isNotEmpty
                                  ? m.displayThinking
                                  : (m.id < 0 &&
                                          _liveThinking.trim().isNotEmpty
                                      ? _liveThinking
                                      : '');
                              final thinkingLive = m.id < 0 &&
                                  _sending &&
                                  thinkingText.isNotEmpty &&
                                  !_planDone &&
                                  !_streamLive;
                              final awaitingAnswer = m.id < 0 &&
                                  _sending &&
                                  _planDone &&
                                  !_streamLive;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: m.isUser
                                    ? _UserBubble(
                                        text: m.content,
                                        contextMenuBuilder:
                                            _selectionToolbar(),
                                      )
                                    : _AssistantBlock(
                                        key: ValueKey('agent-asst-${m.id}'),
                                        text: m.content,
                                        thinking: thinkingText,
                                        thinkingLive: thinkingLive,
                                        awaitingAnswer: awaitingAnswer,
                                        citations: m.citations,
                                        citationShownCount:
                                            _citationRevealCount(m.id),
                                        onLoadMoreCitations: (total) =>
                                            _loadMoreCitations(m.id, total),
                                        inventoryTags: m.inventoryTags,
                                        pendingAction: m.pendingAction,
                                        focusItemId: _focusItemId,
                                        pickedIds: _pickedCitations.keys.toSet(),
                                        onOpen: _openCitation,
                                        onOpenTag: _openInventoryTag,
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

  /// 动态预设优先。
  /// - 全局空会话：规则起步（不拉/不等动态）
  /// - 单篇助手（即使尚无 message）或已有对话：只显示动态结果，未返回前不展示，避免布局跳动
  List<String> _resolvePresetItems() {
    final focused = _focusItem != null || _focusItemId != null;
    final hasMessages = _messages.isNotEmpty;
    final needDynamic = focused || hasMessages;
    final isVideo = _focusIsVideo();
    final isGallery = _focusIsGallery();
    final canComposeVideo = _focusCanComposeVideo();
    final canComposeGallery = _focusCanComposeGallery();

    if (needDynamic) {
      final dynamic = _llmPresets;
      if (dynamic != null && dynamic.isNotEmpty) {
        return _AgentPresetRules.filterCompose(
          dynamic,
          isVideo: isVideo,
          isGallery: isGallery,
          canComposeVideo: canComposeVideo,
          canComposeGallery: canComposeGallery,
        );
      }
      return const [];
    }

    return _AgentPresetRules.starters(focused: false);
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
          pageUrl: focus.sourcePageUrl,
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

/// 阅读锚定：顶栏下紧凑上下文条（无底部分割线）。
class _FocusItemBanner extends StatelessWidget {
  const _FocusItemBanner({
    required this.item,
    required this.onTap,
  });

  final CollectionItem item;
  final VoidCallback onTap;

  static const _brand = Color(0xFF2F6FED);
  static const _soft = Color(0xFFE8F0FF);
  static const _title = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _pageBg = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    final pageUrl = (item.canonicalUrl?.trim().isNotEmpty == true)
        ? item.canonicalUrl!
        : item.url;
    final platform = platformLabel(item.platform, url: pageUrl);
    final rawTitle = (item.title ?? '').trim();
    final title = rawTitle.isEmpty ? '未命名收藏' : rawTitle;

    return Material(
      color: _pageBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
        child: Material(
          color: _soft,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
              child: Row(
                children: [
                  CoverImage(
                    url: item.coverImageUrl,
                    pageUrl: pageUrl,
                    width: 40,
                    height: 40,
                    borderRadius: 8,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '这篇',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _brand,
                            height: 1.1,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: _title,
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (platform.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      platform,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _muted,
                        height: 1.2,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: _muted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 空态：主题色 ✦ 圆标（无光晕）+ 居中标题；全局另有副文。
class _EmptyState extends StatelessWidget {
  const _EmptyState({this.focused = false});

  final bool focused;

  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE8F0FF);
  static const _title = Color(0xFF1F242E);
  static const _sub = Color(0xFF737A85);

  Widget _sparkIcon() {
    return Container(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    if (focused) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sparkIcon(),
              const SizedBox(height: 24),
              const Text(
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
            _sparkIcon(),
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
              '在收藏里更快找到内容',
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

/// 思考完成后、正文未出：轻量 loading。
class _AnswerPendingLoader extends StatelessWidget {
  const _AnswerPendingLoader();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: Color(0xFF9AA1AB),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '正在执行…',
          style: TextStyle(
            fontSize: 13,
            height: 1.2,
            color: const Color(0xFF9AA1AB).withValues(alpha: 0.95),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// 可折叠「思考中… / 思考完成」：任务理解与规划灰字。
class _ThinkingPanel extends StatefulWidget {
  const _ThinkingPanel({
    required this.text,
    this.live = false,
    this.initiallyExpanded = false,
  });

  final String text;
  final bool live;
  final bool initiallyExpanded;

  @override
  State<_ThinkingPanel> createState() => _ThinkingPanelState();
}

class _ThinkingPanelState extends State<_ThinkingPanel> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded || widget.live;
  }

  @override
  void didUpdateWidget(covariant _ThinkingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.live && !oldWidget.live) {
      _expanded = true;
    }
    if (!widget.live && oldWidget.live) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.text.trim();
    if (body.isEmpty) return const SizedBox.shrink();
    final title = widget.live ? '思考中…' : '思考完成';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: widget.live
                        ? const Color(0xFF5C6B7A)
                        : const Color(0xFF9AA1AB),
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 16,
                  color: const Color(0xFF9AA1AB),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.55,
              color: Color(0xFF8B939E),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
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
                  pageUrl: c.pageUrl,
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

class _AssistantBlock extends StatelessWidget {
  const _AssistantBlock({
    super.key,
    required this.text,
    required this.citations,
    required this.citationShownCount,
    required this.onLoadMoreCitations,
    required this.inventoryTags,
    required this.pickedIds,
    required this.onOpen,
    required this.onOpenTag,
    required this.onPick,
    required this.contextMenuBuilder,
    this.thinking = '',
    this.thinkingLive = false,
    this.awaitingAnswer = false,
    this.focusItemId,
    this.pendingAction,
    this.pickEnabled = true,
    this.confirmEnabled = true,
    this.onConfirmAction,
  });

  final String text;
  final String thinking;
  final bool thinkingLive;
  /// 思考完成、正文尚未开始流式
  final bool awaitingAnswer;
  final List<AgentCitation> citations;
  /// 由页面控制：默认 3，点加载更多再增加
  final int citationShownCount;
  final ValueChanged<int> onLoadMoreCitations;
  final List<AgentTagChip> inventoryTags;
  final AgentPendingAction? pendingAction;
  final int? focusItemId;
  final Set<int> pickedIds;
  final ValueChanged<AgentCitation> onOpen;
  final ValueChanged<AgentTagChip> onOpenTag;
  final ValueChanged<AgentCitation> onPick;
  final EditableTextContextMenuBuilder contextMenuBuilder;
  final bool pickEnabled;
  final bool confirmEnabled;
  final ValueChanged<bool>? onConfirmAction;

  static const _brand = Color(0xFF2F6FED);

  /// 阅读锚定：出处列表去掉当前篇（顶栏已展示），只留其它篇。
  List<AgentCitation> get _visibleCitations {
    final fid = focusItemId;
    if (fid == null || fid <= 0) return citations;
    return citations.where((c) => c.itemId != fid).toList(growable: false);
  }

  bool get _showCitations => _visibleCitations.isNotEmpty;

  Future<void> _copyAll(BuildContext context) async {
    final body = text.trim();
    if (body.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: body));
    if (context.mounted) AppToast.show(context, '已复制');
  }

  TranscriptSegment? get _transcriptProgressSegment {
    final pa = pendingAction;
    if (pa == null || !pa.isStartTranscript) return null;
    // 待确认只显示确认条；步骤条仅在 running
    if (pa.status != 'running') return null;
    return TranscriptSegment(
      status: 'pending',
      phase: pa.phase ?? 'queued',
      phaseLabel: pa.phaseLabel ?? '正在生成文稿…',
      phaseHint: pa.phaseHint,
      phaseAt: pa.phaseAt,
    );
  }

  @override
  Widget build(BuildContext context) {
    final showConfirm = pendingAction?.isPending == true && onConfirmAction != null;
    final progressSeg = _transcriptProgressSegment;
    final canCopy = text.trim().isNotEmpty && progressSeg == null;
    final think = thinking.trim();
    final allCites = _visibleCitations;
    final limit = citationShownCount < 1 ? 1 : citationShownCount;
    final shown = allCites.take(limit).toList(growable: false);
    final remaining = allCites.length - shown.length;
    final hasMore = remaining > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (think.isNotEmpty) ...[
          _ThinkingPanel(
            text: think,
            live: thinkingLive,
            initiallyExpanded: thinkingLive,
          ),
          if (awaitingAnswer || text.trim().isNotEmpty)
            const SizedBox(height: 10),
        ],
        if (awaitingAnswer && text.trim().isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: _AnswerPendingLoader(),
          ),
        if (text.trim().isNotEmpty)
          TextSelectionTheme(
            data: const TextSelectionThemeData(
              selectionColor: Color(0x662F6FED),
            ),
            child: AgentMarkdown(
              text,
              contextMenuBuilder: contextMenuBuilder,
            ),
          ),
        if (progressSeg != null) ...[
          const SizedBox(height: 12),
          TranscriptPendingProgress(segment: progressSeg),
        ],
        if (inventoryTags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in inventoryTags)
                _AgentTagChip(tag: tag, onTap: () => onOpenTag(tag)),
            ],
          ),
        ],
        if (canCopy)
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => _copyAll(context),
              tooltip: '复制',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              icon: const Icon(
                Icons.copy_outlined,
                size: 18,
                color: Color(0xFF9AA3AF),
              ),
            ),
          ),
        if (_showCitations) ...[
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
          for (final c in shown) ...[
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
                    pageUrl: c.pageUrl,
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
          if (hasMore)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => onLoadMoreCitations(allCites.length),
                style: TextButton.styleFrom(
                  foregroundColor: _brand,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                child: Text(
                  '加载更多（还有 $remaining 条）',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ),
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
  static const _composeVideoPreset = '整理成一篇文章';
  static const _transcriptPreset = '生成文稿';
  static const _composeGalleryPreset = '根据图片整理成文章';

  static bool _looksLikeVideoCompose(String p) {
    final s = p.trim();
    if (RegExp(r'^生成文稿$|^转写这篇$').hasMatch(s)) return false;
    if (RegExp(r'根据图片').hasMatch(s)) return false;
    return RegExp(r'^整理成一篇文章$|根据转写|转写写一篇').hasMatch(s);
  }

  static bool _looksLikeTranscriptOnly(String p) =>
      RegExp(r'^生成文稿$|^转写这篇$|开始转写|开始生成').hasMatch(p.trim());

  static bool _looksLikeGalleryCompose(String p) =>
      RegExp(r'这组图|图集整理|根据图片整理|把.*图.*整理成|整理成笔记')
          .hasMatch(p);

  /// 视频：未有文稿时留「生成文稿」+ 成文；图集：可留整理成文；互斥滤掉对方的 compose 预设。
  static List<String> filterCompose(
    List<String> presets, {
    required bool isVideo,
    required bool isGallery,
    required bool canComposeVideo,
    required bool canComposeGallery,
  }) {
    if (isVideo && !canComposeVideo) {
      final kept = presets
          .where((p) => _looksLikeVideoCompose(p) || _looksLikeTranscriptOnly(p))
          .toList();
      if (kept.isEmpty) {
        return const [_transcriptPreset, _composeVideoPreset];
      }
      final hasCompose = kept.any(_looksLikeVideoCompose);
      return List<String>.unmodifiable([
        _transcriptPreset,
        if (hasCompose)
          kept.firstWhere(_looksLikeVideoCompose)
        else
          _composeVideoPreset,
      ]);
    }
    var out = presets.toList();
    if (!canComposeVideo) {
      out = out
          .where(
            (p) => !_looksLikeVideoCompose(p) && !_looksLikeTranscriptOnly(p),
          )
          .toList();
    } else {
      out = out.where((p) => !_looksLikeTranscriptOnly(p)).toList();
    }
    if (!canComposeGallery) {
      out = out.where((p) => !_looksLikeGalleryCompose(p)).toList();
    }
    if (isGallery && canComposeGallery) {
      final hasGallery = out.any(_looksLikeGalleryCompose);
      if (!hasGallery) {
        out = [_composeGalleryPreset, ...out];
      }
    }
    return List<String>.unmodifiable(out);
  }

  static List<String> starters({
    required bool focused,
    bool isVideo = false,
    bool isGallery = false,
    bool canComposeVideo = false,
    bool canComposeGallery = false,
  }) {
    if (focused) {
      if (isVideo && !canComposeVideo) {
        return const [_transcriptPreset, _composeVideoPreset];
      }
      if (isGallery && canComposeGallery) {
        return filterCompose(
          const [
            _composeGalleryPreset,
            '这篇的核心观点是什么？',
            '还有哪些相关收藏？',
          ],
          isVideo: isVideo,
          isGallery: isGallery,
          canComposeVideo: canComposeVideo,
          canComposeGallery: canComposeGallery,
        );
      }
      return filterCompose(
        const [
          '这篇的核心观点是什么？',
          _composeVideoPreset,
          '还有哪些相关收藏？',
        ],
        isVideo: isVideo,
        isGallery: isGallery,
        canComposeVideo: canComposeVideo,
        canComposeGallery: canComposeGallery,
      );
    }
    return const [
      '查找关于…',
      '类似××的内容有哪些',
      '我存过哪些关于…',
    ];
  }

  static List<String> fromAssistant(
    AgentMessage message, {
    required bool focused,
    bool isVideo = false,
    bool isGallery = false,
    bool canComposeVideo = false,
    bool canComposeGallery = false,
  }) {
    // 确认写入 / 转写进行中：不再挂预设
    if (message.pendingAction?.isPending == true ||
        message.pendingAction?.isTranscriptJobActive == true) {
      return const [];
    }

    if (message.citations.isNotEmpty) {
      final title = message.citations.first.title.trim();
      final short = title.length > 12 ? '${title.substring(0, 12)}…' : title;
      return [
        if (short.isNotEmpty) '深入解读《$short》',
        '还有哪些相关收藏？',
        '查找关于…',
      ];
    }
    if (focused) {
      if (isVideo && !canComposeVideo) {
        return const [_transcriptPreset, _composeVideoPreset];
      }
      if (isGallery && canComposeGallery) {
        return filterCompose(
          const [
            '再展开说明',
            _composeGalleryPreset,
            '还有哪些相关收藏？',
          ],
          isVideo: isVideo,
          isGallery: isGallery,
          canComposeVideo: canComposeVideo,
          canComposeGallery: canComposeGallery,
        );
      }
      return filterCompose(
        const [
          '再展开说明',
          _composeVideoPreset,
          '还有哪些相关收藏？',
        ],
        isVideo: isVideo,
        isGallery: isGallery,
        canComposeVideo: canComposeVideo,
        canComposeGallery: canComposeGallery,
      );
    }
    // 全局助手：意图搜索（无深挖）
    return const [
      '查找关于…',
      '类似××的内容有哪些',
      '我存过哪些关于…',
    ];
  }
}

class _AgentTagChip extends StatelessWidget {
  const _AgentTagChip({required this.tag, required this.onTap});

  final AgentTagChip tag;
  final VoidCallback onTap;

  static const _ink = Color(0xFF1F242E);
  static const _fill = Color(0xFFF5F7FA);
  static const _accent = Color(0xFF2F6FED);

  String get _label {
    final n = tag.name.trim();
    if (n.isEmpty) return '';
    return n.startsWith('#') ? n : '#$n';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _fill,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 9, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 2,
                height: 12,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  letterSpacing: 0.1,
                  color: _ink.withValues(alpha: 0.88),
                ),
              ),
              if (tag.itemCount > 0) ...[
                const SizedBox(width: 5),
                Text(
                  '${tag.itemCount}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                    color: _ink.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 2),
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
