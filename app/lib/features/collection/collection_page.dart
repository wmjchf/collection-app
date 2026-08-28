import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/collection/system_filter_models.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/collection/trash_page.dart';
import 'package:super_collection/features/settings/settings_page.dart';

/// 我的收藏（系统分类 + 标签）
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
  });

  /// 是否为当前 Tab；切回时静默刷新数量。
  final bool isActive;

  /// 外部递增时静默刷新（分享入库、解析完成）。
  final int refreshTick;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage>
    with SingleTickerProviderStateMixin {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _inputBg = Color(0xFFF5F7FA);
  static const _searchRadius = 20.0;

  final _tagsRepo = TagsRepository();
  final _systemFiltersRepo = SystemFiltersRepository();
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchFieldKey = GlobalKey();
  final _bodyStackKey = GlobalKey();

  late final AnimationController _searchAnim;
  late final Animation<double> _searchExpand;

  List<Tag> _tags = const [];
  List<SystemFilter> _systemFilters = const [];
  bool _loading = true;
  String? _error;
  /// 搜索栏挂载中（含收起动画）
  bool _tagSearchMounted = false;
  /// 已展开：可输入 / 显示结果
  bool _tagSearchOpen = false;
  /// 浮层与搜索框对齐的 left / width（相对 body Stack）
  double? _overlayLeft;
  double? _overlayWidth;

  @override
  void initState() {
    super.initState();
    _searchAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _searchExpand = CurvedAnimation(
      parent: _searchAnim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _load();
  }

  @override
  void dispose() {
    _searchAnim.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
    }
    if (!widget.isActive && oldWidget.isActive && _tagSearchMounted) {
      _closeTagSearch();
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  List<Tag> get _visibleTags => List<Tag>.from(_tags);

  bool get _showSearchOverlay {
    if (!_tagSearchOpen) return false;
    return _searchController.text.trim().isNotEmpty;
  }

  List<Tag> get _filteredTags {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return _visibleTags
        .where((t) => t.name.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  void _openTagSearch() {
    if (_tagSearchMounted && _searchAnim.isAnimating) return;
    setState(() {
      _tagSearchMounted = true;
      _tagSearchOpen = true;
    });
    _searchAnim.forward().whenComplete(() {
      if (!mounted || !_tagSearchOpen) return;
      _searchFocus.requestFocus();
    });
  }

  Future<void> _closeTagSearch() async {
    if (!_tagSearchMounted) return;
    _searchController.clear();
    _searchFocus.unfocus();
    if (mounted) setState(() => _tagSearchOpen = false);
    await _searchAnim.reverse();
    if (!mounted) return;
    setState(() => _tagSearchMounted = false);
  }

  void _onSearchChanged(String _) {
    setState(() {});
    _scheduleSyncOverlayGeometry();
  }

  void _scheduleSyncOverlayGeometry() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncOverlayGeometry();
    });
  }

  void _syncOverlayGeometry() {
    if (!_showSearchOverlay) {
      if (_overlayLeft != null || _overlayWidth != null) {
        setState(() {
          _overlayLeft = null;
          _overlayWidth = null;
        });
      }
      return;
    }
    final fieldBox =
        _searchFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox =
        _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox == null ||
        stackBox == null ||
        !fieldBox.hasSize ||
        !stackBox.hasSize) {
      return;
    }
    final fieldOrigin = fieldBox.localToGlobal(Offset.zero);
    final stackOrigin = stackBox.localToGlobal(Offset.zero);
    final left = fieldOrigin.dx - stackOrigin.dx;
    final width = fieldBox.size.width;
    if (_overlayLeft == left && _overlayWidth == width) return;
    setState(() {
      _overlayLeft = left;
      _overlayWidth = width;
    });
  }

  Future<void> _load({bool quiet = false}) async {
    final showSpinner = !quiet || _systemFilters.isEmpty;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        _tagsRepo.listTags(),
        _systemFiltersRepo.listFilters(),
      ]);
      if (!mounted) return;
      final filterResult =
          results[1] as ({List<SystemFilter> filters, List<SystemFilter> others});
      setState(() {
        _tags = results[0] as List<Tag>;
        _systemFilters = filterResult.filters;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!quiet) _error = '加载失败，请检查网络或后端是否启动';
      });
    }
  }

  void _openSystemFilter(SystemFilter filter) {
    final page = filter.code == 'trash'
        ? const TrashPage()
        : SystemFilterListPage(
            code: filter.code,
            title: filter.name,
          );
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => page,
      ),
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  void _openTag(Tag tag) {
    if (_tagSearchMounted) {
      _searchController.clear();
      _searchFocus.unfocus();
      _searchAnim.value = 0;
      setState(() {
        _tagSearchOpen = false;
        _tagSearchMounted = false;
      });
    }
    Navigator.of(context)
        .push(
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
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 0,
      actionsPadding: EdgeInsets.zero,
      automaticallyImplyLeading: false,
      centerTitle: false,
      // 整条顶栏自绘：搜索从标签右缘向左展开；标签/设置间距对齐首页
      title: AnimatedBuilder(
        animation: _searchExpand,
        child: _tagSearchMounted ? _buildHeaderSearchField() : null,
        builder: (context, searchField) {
          final t = _searchExpand.value;
          final showCancel = t > 0.7;
          return SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: 40,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Row(
                children: [
                  Expanded(
                    key: _searchFieldKey,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        IgnorePointer(
                          ignoring: t > 0.05,
                          child: Opacity(
                            opacity: (1 - t * 1.4).clamp(0.0, 1.0),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '我的收藏',
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: _text,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '搜索标签',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 36,
                                  ),
                                  onPressed:
                                      t > 0.01 ? null : _openTagSearch,
                                  icon: SvgPicture.asset(
                                    'assets/icons/tags_inactive.svg',
                                    width: 24,
                                    height: 24,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (searchField != null)
                          Align(
                            alignment: Alignment.centerRight,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // fullW = 标题区 + 标签；右缘对齐标签右缘
                                final fullW = constraints.maxWidth;
                                final width =
                                    (fullW * t).clamp(0.0, fullW);
                                if (width < 1) {
                                  return const SizedBox.shrink();
                                }
                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    _searchRadius,
                                  ),
                                  child: SizedBox(
                                    width: width,
                                    height: 40,
                                    child: OverflowBox(
                                      alignment: Alignment.centerRight,
                                      minWidth: fullW,
                                      maxWidth: fullW,
                                      child: SizedBox(
                                        width: fullW,
                                        height: 40,
                                        child: searchField,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      IgnorePointer(
                        ignoring: showCancel,
                        child: Opacity(
                          opacity: (1 - t * 2.2).clamp(0.0, 1.0),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              tooltip: '设置',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                              onPressed: t > 0.01
                                  ? null
                                  : () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) =>
                                              const SettingsPage(),
                                        ),
                                      );
                                    },
                              icon: const Icon(
                                Icons.settings_outlined,
                                size: 22,
                                color: _text,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: !showCancel,
                        child: Opacity(
                          opacity: ((t - 0.7) / 0.3).clamp(0.0, 1.0),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton(
                              onPressed: _closeTagSearch,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 36),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: _text,
                                ),
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
          );
        },
      ),
      actions: const <Widget>[],
    );
  }

  Widget _buildHeaderSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      onChanged: _onSearchChanged,
      onSubmitted: (_) {},
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 15, color: _text, height: 1.2),
      decoration: InputDecoration(
        hintText: '搜索标签',
        hintStyle: const TextStyle(fontSize: 15, color: _muted),
        prefixIcon:
            const Icon(Icons.search_rounded, color: _muted, size: 22),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, color: _muted, size: 20),
                onPressed: () {
                  _searchController.clear();
                  _onSearchChanged('');
                  _searchFocus.requestFocus();
                },
              ),
        filled: true,
        fillColor: _inputBg,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_searchRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_searchRadius),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_searchRadius),
          borderSide: const BorderSide(color: Color(0xFFB8CCFA), width: 1),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showSearchOverlay &&
        (_overlayLeft == null || _overlayWidth == null)) {
      _scheduleSyncOverlayGeometry();
    }

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Stack(
        key: _bodyStackKey,
        clipBehavior: Clip.none,
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (_loading && _systemFilters.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  )
                else if (_error != null && _systemFilters.isEmpty)
                  _ErrorCard(message: _error!, onRetry: _load)
                else if (_systemFilters.isNotEmpty)
                  Column(
                    children: [
                      if (_systemFilters.any((e) => e.code == 'unread'))
                        _EntityGroup(
                          entries: [
                            for (final f in _systemFilters
                                .where((e) => e.code == 'unread'))
                              _EntityEntry(
                                title: f.name,
                                countLabel: f.countLabel,
                                icon: _CollectionNavIcon.forSystemCode(
                                  f.code,
                                ),
                                onTap: () => _openSystemFilter(f),
                              ),
                          ],
                        ),
                      if (_systemFilters.any((f) => f.code != 'unread')) ...[
                        if (_systemFilters.any((e) => e.code == 'unread'))
                          const SizedBox(height: 16),
                        _EntityGroup(
                          entries: [
                            for (final f in _systemFilters
                                .where((e) => e.code != 'unread'))
                              _EntityEntry(
                                title: f.name,
                                countLabel: f.countLabel,
                                icon: _CollectionNavIcon.forSystemCode(
                                  f.code,
                                ),
                                onTap: () => _openSystemFilter(f),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (_showSearchOverlay) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeTagSearch,
                child: const ColoredBox(color: Color(0x33000000)),
              ),
            ),
            Positioned(
              left: (_overlayLeft ?? 20) + 4,
              width: (_overlayWidth ??
                      (MediaQuery.sizeOf(context).width - 20 - 44)) -
                  8,
              top: -4,
              child: _TagSearchOverlay(
                query: _searchController.text.trim(),
                tags: _filteredTags,
                onTap: _openTag,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
class _TagSearchOverlay extends StatelessWidget {
  const _TagSearchOverlay({
    required this.query,
    required this.tags,
    required this.onTap,
  });

  final String query;
  final List<Tag> tags;
  final ValueChanged<Tag> onTap;

  static const _text = Color(0xFF1F242E);
  static const _muted = Color(0xFF737A85);
  static const _maxHeight = 280.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8ECF0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: tags.isEmpty
              ? Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                  child: Text(
                    '没有「$query」相关的标签',
                    style: const TextStyle(
                      fontSize: 13,
                      color: _muted,
                      height: 1.4,
                    ),
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: _maxHeight),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    primary: false,
                    physics: const ClampingScrollPhysics(),
                    itemCount: tags.length,
                    separatorBuilder: (context, _) =>
                        const Divider(
                      height: 1,
                      indent: 12,
                      endIndent: 12,
                      color: Color(0xFFF0F2F5),
                    ),
                    itemBuilder: (context, index) {
                      final tag = tags[index];
                      return InkWell(
                        onTap: () => onTap(tag),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${tag.name}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: _text,
                                  ),
                                ),
                              ),
                              Text(
                                tag.countLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: _muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

class _CollectionNavIcon {
  const _CollectionNavIcon({
    required this.icon,
    required this.background,
  });

  final IconData icon;
  final Color background;

  static _CollectionNavIcon forSystemCode(String code) {
    switch (code) {
      case 'unread':
        return const _CollectionNavIcon(
          icon: Icons.adjust,
          background: Color(0xFF5B8FF9),
        );
      case 'all':
        return const _CollectionNavIcon(
          icon: Icons.format_list_bulleted_rounded,
          background: Color(0xFF6E788C),
        );
      case 'today':
        return const _CollectionNavIcon(
          icon: Icons.calendar_today_rounded,
          background: Color(0xFFFF9F43),
        );
      case 'starred':
        return const _CollectionNavIcon(
          icon: Icons.star_rounded,
          background: Color(0xFFFFC43D),
        );
      case 'parsed':
        return const _CollectionNavIcon(
          icon: Icons.article_rounded,
          background: Color(0xFF56CC8C),
        );
      case 'annotated':
        return const _CollectionNavIcon(
          icon: Icons.edit_rounded,
          background: Color(0xFFA270F5),
        );
      case 'recent_read':
        return const _CollectionNavIcon(
          icon: Icons.schedule_rounded,
          background: Color(0xFF40BAC4),
        );
      case 'archived':
        return const _CollectionNavIcon(
          icon: Icons.inventory_2_rounded,
          background: Color(0xFF96A0AF),
        );
      case 'trash':
        return const _CollectionNavIcon(
          icon: Icons.delete_outline_rounded,
          background: Color(0xFFF56C6C),
        );
      default:
        return const _CollectionNavIcon(
          icon: Icons.circle,
          background: Color(0xFF5B8FF9),
        );
    }
  }
}

class _EntityEntry {
  const _EntityEntry({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String countLabel;
  final _CollectionNavIcon icon;
  final VoidCallback onTap;
}

class _EntityGroup extends StatelessWidget {
  const _EntityGroup({required this.entries});

  final List<_EntityEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Text(
          '暂无内容',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: _CollectionColors.muted),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _NavRow(
              title: entries[i].title,
              countLabel: entries[i].countLabel,
              icon: entries[i].icon,
              onTap: entries[i].onTap,
            ),
            if (i < entries.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                indent: 14,
                endIndent: 14,
                color: _CollectionColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 14, color: _CollectionColors.muted),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.title,
    required this.countLabel,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String countLabel;
  final _CollectionNavIcon icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: icon.background,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon.icon,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    color: _CollectionColors.text,
                  ),
                ),
              ),
              Text(
                countLabel,
                style: const TextStyle(
                  fontSize: 15,
                  color: _CollectionColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '›',
                style: TextStyle(
                  fontSize: 18,
                  color: _CollectionColors.muted,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

abstract final class _CollectionColors {
  static const text = Color(0xFF1F242E);
  static const muted = Color(0xFF737A85);
  static const divider = Color(0xFFF0F1F4);
}
