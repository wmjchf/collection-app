import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/onboarding/seed_tag_catalog.dart';
import 'package:super_collection/features/onboarding/seed_tags_prefs.dart';
import 'package:super_collection/features/shell/main_shell.dart';
import 'package:super_collection/features/shortcuts/shortcut_inbound.dart';

/// 首次引导：从种子库多选标签（可跳过），写入个人库后再进主壳。
class SeedTagsPickPage extends StatefulWidget {
  const SeedTagsPickPage({super.key, this.userId});

  final int? userId;

  @override
  State<SeedTagsPickPage> createState() => _SeedTagsPickPageState();
}

class _SeedTagsPickPageState extends State<SeedTagsPickPage> {
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);

  final _repo = TagsRepository();
  final _selected = <String>{};
  bool _saving = false;

  void _toggle(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  Future<void> _finish({required bool createSelected}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (createSelected && _selected.isNotEmpty) {
        await _createSelectedTags();
      }
      await SeedTagsPrefs.markDone(userId: widget.userId);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const MainShell()),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ShortcutInbound.flushPending();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, '创建失败，请稍后重试');
    }
  }

  Future<void> _createSelectedTags() async {
    if (_selected.isEmpty) return;

    final index = seedTagIndex();
    final groupByChild = seedTagGroupByChildKey();
    final existing = await _repo.listTags();
    final idByName = {
      for (final t in existing.where((e) => !e.isSystem))
        t.name.trim().toLowerCase(): t.id,
    };

    Future<int> ensureRoot(String name) async {
      final nameKey = name.trim().toLowerCase();
      final existed = idByName[nameKey];
      if (existed != null) return existed;
      try {
        final tag = await _repo.createTag(name);
        idByName[nameKey] = tag.id;
        return tag.id;
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          final again = await _repo.listTags();
          for (final t in again.where((x) => !x.isSystem)) {
            idByName[t.name.trim().toLowerCase()] = t.id;
          }
          final id = idByName[nameKey];
          if (id != null) return id;
        }
        rethrow;
      }
    }

    Future<void> ensureChild(String name, {required int parentId}) async {
      final nameKey = name.trim().toLowerCase();
      if (idByName.containsKey(nameKey)) return;
      try {
        final tag = await _repo.createTag(name, parentId: parentId);
        idByName[nameKey] = tag.id;
      } on ApiException catch (e) {
        if (e.statusCode == 409) {
          final again = await _repo.listTags();
          for (final t in again.where((x) => !x.isSystem)) {
            idByName[t.name.trim().toLowerCase()] = t.id;
          }
          return;
        }
        rethrow;
      }
    }

    // 按组：先建父，再挂选中的子
    final parentIds = <String, int>{};
    for (final key in _selected) {
      final group = groupByChild[key];
      final item = index[key];
      if (group == null || item == null) continue;

      final parentId = parentIds[group.key] ??=
          await ensureRoot(group.title);
      await ensureChild(item.name, parentId: parentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _selected.length;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '选几个常用标签',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '先挑几个，之后还能在「我的标签」里改。名单为试用数据，可随时调整。',
                    style: TextStyle(
                      fontSize: 14,
                      color: _muted.withValues(alpha: 0.95),
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                itemCount: kSeedTagCatalog.length,
                itemBuilder: (context, index) {
                  final group = kSeedTagCatalog[index];
                  return Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 20),
                    child: _SeedGroupBlock(
                      group: group,
                      selected: _selected,
                      onToggle: _toggle,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving
                          ? null
                          : () => _finish(createSelected: true),
                      style: FilledButton.styleFrom(
                        backgroundColor: _blue,
                        disabledBackgroundColor:
                            _blue.withValues(alpha: 0.45),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _saving
                            ? '创建中…'
                            : (count == 0 ? '进入应用' : '添加 $count 个标签'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _saving
                        ? null
                        : () => _finish(createSelected: false),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '暂时跳过',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeedGroupBlock extends StatelessWidget {
  const _SeedGroupBlock({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  final SeedTagGroup group;
  final Set<String> selected;
  final void Function(String key) onToggle;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _chipBg = Color(0xFFF5F7FA);
  static const _chipOn = Color(0xFFE5EDFF);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _muted,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in group.items) _chip(item.key, item.name),
          ],
        ),
      ],
    );
  }

  Widget _chip(String key, String name) {
    final on = selected.contains(key);
    return GestureDetector(
      onTap: () => onToggle(key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? _chipOn : _chipBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: on ? const Color(0xFFB8CCFA) : const Color(0xFFE8ECF0),
          ),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: on ? _blue : _text,
          ),
        ),
      ),
    );
  }
}
