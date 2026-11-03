import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_subpage_app_bar.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_markdown.dart';
import 'package:super_collection/features/agent/agent_models.dart';
import 'package:super_collection/features/agent/agent_repository.dart';
import 'package:super_collection/features/items/item_list_tile.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/items/item_reading_page.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// 私人助手（P1：查收藏 + 出处）
class AgentPage extends StatefulWidget {
  const AgentPage({super.key});

  @override
  State<AgentPage> createState() => _AgentPageState();
}

class _AgentPageState extends State<AgentPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _brand = Color(0xFF2F6FED);
  static const _brandSoft = Color(0xFFE8F0FF);

  final _repo = AgentRepository();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  int? _conversationId;
  final List<AgentMessage> _messages = [];
  bool _booting = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    try {
      final list = await _repo.listConversations();
      if (!mounted) return;
      if (list.isNotEmpty) {
        final detail = await _repo.getConversation(list.first.id);
        if (!mounted) return;
        setState(() {
          _conversationId = detail.conversation.id;
          _messages
            ..clear()
            ..addAll(detail.messages.where(
              (m) => m.isUser || m.isAssistant,
            ));
          _booting = false;
        });
        // 长会话贴底看最新；短会话 max≈0，自然从顶部起
        _scrollToEnd(jump: true);
        return;
      }
      final conv = await _repo.createConversation();
      if (!mounted) return;
      setState(() {
        _conversationId = conv.id;
        _messages.clear();
        _booting = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = e.message;
      });
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _booting = false;
        _error = '加载失败';
      });
    }
  }

  Future<void> _ensureConversation() async {
    if (_conversationId != null) return;
    final conv = await _repo.createConversation();
    _conversationId = conv.id;
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;

    final allowed = await ensurePlanFeatures(
      context,
      requirements: [
        (has: (f) => f.aiAgent, tier: UsagePlan.prince),
      ],
    );
    if (!allowed || !mounted) return;

    setState(() => _sending = true);
    if (preset == null) _input.clear();

    // 乐观展示用户消息
    final optimistic = AgentMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      role: 'user',
      content: text,
    );
    setState(() => _messages.add(optimistic));
    _scrollToEnd();

    try {
      await _ensureConversation();
      final id = _conversationId!;
      final result = await _repo.sendMessage(
        conversationId: id,
        content: text,
      );
      if (!mounted) return;
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == optimistic.id);
        if (idx >= 0) {
          _messages[idx] = result.userMessage;
        }
        _messages.add(result.assistantMessage);
        _sending = false;
      });
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == optimistic.id);
        _sending = false;
      });
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((m) => m.id == optimistic.id);
        _sending = false;
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
    });
    try {
      if (oldId != null) {
        await _repo.archiveConversation(oldId);
      }
      final conv = await _repo.createConversation();
      if (!mounted) return;
      setState(() {
        _conversationId = conv.id;
        _messages.clear();
        _booting = false;
      });
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
                  color: canClear ? _text : const Color(0xFFC5CAD3),
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
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
                        ? const _EmptyState()
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                            itemCount: _messages.length + (_sending ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_sending && index == _messages.length) {
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
                                    ? _UserBubble(text: m.content)
                                    : _AssistantBlock(
                                        text: m.content,
                                        citations: m.citations,
                                        onOpen: _openCitation,
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
            onSend: () => _send(),
          ),
        ],
      ),
    );
  }

}

/// 空态：品牌气场的暗绿光核 + 薄荷 ✦，居中标题/副文（避免浅蓝「后台」感）。
class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState>
    with SingleTickerProviderStateMixin {
  static const _ink = Color(0xFF101612);
  static const _moss = Color(0xFF1C2A22);
  static const _mint = Color(0xFFB7E0C6);
  static const _title = Color(0xFF161C18);
  static const _sub = Color(0xFF6B746E);

  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 24, 36, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _breath,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(_breath.value);
                final glow = 0.22 + 0.18 * t;
                final ring = 1.0 + 0.04 * t;
                return SizedBox(
                  width: 128,
                  height: 128,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 外层弥散光
                      Transform.scale(
                        scale: ring,
                        child: Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                _mint.withValues(alpha: glow * 0.55),
                                _mint.withValues(alpha: glow * 0.12),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // 细轨道环
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _mint.withValues(alpha: 0.28 + 0.12 * t),
                            width: 1,
                          ),
                        ),
                      ),
                      // 暗绿核
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            center: Alignment(-0.35, -0.4),
                            radius: 1.05,
                            colors: [
                              Color(0xFF2A3D32),
                              _moss,
                              _ink,
                            ],
                            stops: [0.0, 0.45, 1.0],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _mint.withValues(alpha: 0.22 + 0.1 * t),
                              blurRadius: 28,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: _ink.withValues(alpha: 0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '✦',
                          style: TextStyle(
                            fontSize: 28,
                            height: 1,
                            color: _mint.withValues(alpha: 0.92 + 0.08 * t),
                            shadows: [
                              Shadow(
                                color: _mint.withValues(alpha: 0.55),
                                blurRadius: 12,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
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
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: const [
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
        color: const Color(0xFF161C18).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF1C2A22).withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: Color(0xFF3D4A42),
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

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

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
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF1F242E),
            height: 1.45,
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
    required this.onOpen,
  });

  final String text;
  final List<AgentCitation> citations;
  final ValueChanged<AgentCitation> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AgentMarkdown(text),
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
            ItemListTile(
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final double bottomInset;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset.clamp(0, 28)),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8EBF0))),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7FA),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE6E8EB)),
        ),
        child: Row(
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
                style: const TextStyle(fontSize: 15, color: Color(0xFF1F242E)),
                decoration: const InputDecoration(
                  hintText: '跟助手说点什么…',
                  hintStyle: TextStyle(color: Color(0xFF737A85), fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: enabled ? const Color(0xFF2F6FED) : const Color(0xFFB8CCFA),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onSend : null,
                child: const SizedBox(
                  width: 32,
                  height: 32,
                  child: Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
