import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
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

  static const _prompts = [
    '我存过哪些讲「长期主义」的？',
    '这篇里「注意力」是怎么讲的？',
    '把这两篇关于写作的对照一下',
  ];

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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
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
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
                            children: _buildEmpty(),
                          )
                        : ListView.builder(
                            // reverse：默认贴在底部，进页无需动画滚动
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                            itemCount: _messages.length + (_sending ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_sending && index == 0) {
                                return const Padding(
                                  padding: EdgeInsets.only(bottom: 14, top: 2),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _ThinkingIndicator(),
                                  ),
                                );
                              }
                              final msgIndex = _sending ? index - 1 : index;
                              final m =
                                  _messages[_messages.length - 1 - msgIndex];
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

  List<Widget> _buildEmpty() {
    return [
      const Text(
        '你的私人助手。',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          color: _text,
          height: 1.3,
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        '先帮你查库、找出处；之后还能一起整理、创作。',
        style: TextStyle(fontSize: 15, color: _muted, height: 1.45),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: const [
          _CapChip(label: '查收藏', active: true),
          _CapChip(label: '整理 · 即将', active: false),
          _CapChip(label: '创作 · 即将', active: false),
        ],
      ),
      const SizedBox(height: 22),
      const Text(
        '现在可以这样用',
        style: TextStyle(fontSize: 13, color: _muted, fontWeight: FontWeight.w500),
      ),
      const SizedBox(height: 10),
      for (final p in _prompts) ...[
        _PromptCard(label: p, onTap: () => _send(p)),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 24),
    ];
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

class _CapChip extends StatelessWidget {
  const _CapChip({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFE8F0FF) : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(999),
        border: active
            ? null
            : Border.all(color: const Color(0xFFE6E8EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: active ? const Color(0xFF2F6FED) : const Color(0xFF9AA1AB),
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE8EBF0)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1F242E),
              height: 1.4,
            ),
          ),
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
