import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/ai_organize_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/settings/quota_gate.dart';

/// 弹出 AI 归类：生成建议 → 预览 → 应用。成功返回 true。
Future<bool?> showAiOrganizeSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x59000000),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: const _AiOrganizeSheet(),
      );
    },
  );
}

class _AiOrganizeSheet extends StatefulWidget {
  const _AiOrganizeSheet();

  @override
  State<_AiOrganizeSheet> createState() => _AiOrganizeSheetState();
}

class _AiOrganizeSheetState extends State<_AiOrganizeSheet> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _aiAccent = Color(0xFF6B5CE7);
  static const _handle = Color(0xFFE5E8ED);
  static const _divider = Color(0xFFF0F1F4);

  final _repo = TagModulesRepository();

  bool _loading = true;
  bool _applying = false;
  String? _error;
  AiOrganizeProposal? _proposal;
  String? _suggestMessage;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _error = null;
      _proposal = null;
    });
    try {
      final result = await _repo.suggestAiOrganize();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _proposal = result.proposal;
        _suggestMessage = result.message;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '生成失败，请稍后重试';
      });
    }
  }

  Future<void> _apply() async {
    final proposal = _proposal;
    if (proposal == null || _applying) return;
    setState(() => _applying = true);
    try {
      final result = await _repo.applyAiOrganize(proposal);
      if (!mounted) return;
      AppToast.show(context, result.message);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      await handleApiException(context, e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _applying = false);
      AppToast.show(context, '应用失败，请稍后重试');
    }
  }

  void _close() {
    if (_applying) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.78;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + (bottom > 0 ? bottom : 0)),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
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
                SizedBox(
                  height: 27,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_outlined,
                        size: 18,
                        color: _aiAccent,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'AI 归类',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _text,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _close,
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 32,
                          height: 32,
                          child: Icon(
                            Icons.close_rounded,
                            size: 22,
                            color: _muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(child: _buildBody()),
                if (_proposal != null && !_loading) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _applying ? null : _apply,
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _blue.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: _applying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '应用归类',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _blue, strokeWidth: 2.4),
            SizedBox(height: 16),
            Text(
              '正在梳理标签结构…',
              style: TextStyle(fontSize: 14, color: _muted),
            ),
          ],
        ),
      );
    }

    if (_error != null && _proposal == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.45, color: _muted),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _generate,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    final proposal = _proposal!;
    return ListView(
      shrinkWrap: true,
      children: [
        if (_suggestMessage != null) ...[
          Text(
            _suggestMessage!,
            style: const TextStyle(fontSize: 13, height: 1.4, color: _muted),
          ),
          const SizedBox(height: 12),
        ],
        for (var i = 0; i < proposal.modules.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          _ModulePreview(module: proposal.modules[i]),
        ],
        if (proposal.ungroupedTags.isNotEmpty) ...[
          const SizedBox(height: 14),
          _UngroupedPreview(tags: proposal.ungroupedTags),
        ],
        const SizedBox(height: 4),
        const Divider(height: 24, color: _divider),
        const Text(
          '确认后会新建建议的模块，并按方案调整标签归属。未出现在方案中的标签保持原位。',
          style: TextStyle(fontSize: 12, height: 1.4, color: _muted),
        ),
      ],
    );
  }
}

class _ModulePreview extends StatelessWidget {
  const _ModulePreview({required this.module});

  final AiOrganizeModuleProposal module;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _blueSoft = Color(0xFFE5EDFF);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _blue,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                module.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: module.isNew ? _blueSoft : const Color(0xFFF4F6F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                module.isNew ? '新建' : '已有',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: module.isNew ? _blue : _muted,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final t in module.tags)
              Text(
                t.name.startsWith('#') ? t.name : '#${t.name}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _blue,
                  height: 1.25,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _UngroupedPreview extends StatelessWidget {
  const _UngroupedPreview({required this.tags});

  final List<AiOrganizeTagBrief> tags;

  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.inbox_outlined, size: 16, color: _muted),
            SizedBox(width: 6),
            Text(
              '仍放未归类',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final t in tags)
              Text(
                t.name.startsWith('#') ? t.name : '#${t.name}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _blue,
                  height: 1.25,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
