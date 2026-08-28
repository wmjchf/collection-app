import 'package:flutter/material.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';

/// 标签搜索页（交互与样式对齐首页 [SearchPage]）
class TagsSearchPage extends StatefulWidget {
  const TagsSearchPage({
    super.key,
    required this.tags,
  });

  final List<Tag> tags;

  @override
  State<TagsSearchPage> createState() => _TagsSearchPageState();
}

class _TagsSearchPageState extends State<TagsSearchPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _blue = Color(0xFF2F6FED);
  static const _inputBg = Color(0xFFF7F7FA);

  final _tagsRepo = TagsRepository();
  final _controller = TextEditingController();
  final _focus = FocusNode();

  String _query = '';

  List<Tag> get _baseTags => widget.tags;

  List<Tag> get _hits {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _baseTags.where((t) => t.name.toLowerCase().contains(q)).toList();
  }

  bool get _searched => _query.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _unfocusSearch() => _focus.unfocus();

  void _onQueryChanged(String value) {
    setState(() => _query = value);
  }

  void _openTag(Tag tag) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: tag.name,
          loader: ({required limit, required offset}) => _tagsRepo.listTagItems(
            tag.id,
            limit: limit,
            offset: offset,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: _inputBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.search,
                            size: 18,
                            color: _muted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textInputAction: TextInputAction.search,
                              onChanged: _onQueryChanged,
                              onTapOutside: (_) => _unfocusSearch(),
                              onSubmitted: (_) => _unfocusSearch(),
                              style: const TextStyle(
                                fontSize: 15,
                                color: _text,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                hintText: '搜索标签',
                                hintStyle: TextStyle(
                                  fontSize: 15,
                                  color: _muted,
                                ),
                              ),
                            ),
                          ),
                          if (_controller.text.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                _onQueryChanged('');
                              },
                              child: const Icon(
                                Icons.close,
                                size: 16,
                                color: _muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 15,
                        color: _blue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: _unfocusSearch,
                behavior: HitTestBehavior.translucent,
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_searched) {
      return const Center(
        child: Text(
          '输入关键词搜索标签',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    final hits = _hits;
    if (hits.isEmpty) {
      return const Center(
        child: Text(
          '无匹配结果',
          style: TextStyle(fontSize: 14, color: _muted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: hits.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '找到 ${hits.length} 个标签',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          );
        }
        final tag = hits[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: () => _openTag(tag),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tag.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: _text,
                        ),
                      ),
                    ),
                    Text(
                      tag.countLabel,
                      style: const TextStyle(fontSize: 14, color: _muted),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '›',
                      style: TextStyle(fontSize: 18, color: _muted, height: 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
