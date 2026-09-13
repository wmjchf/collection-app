import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/features/collection/collection_tag_modules_section.dart';
import 'package:super_collection/features/collection/create_module_sheet.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/system_filter_list_page.dart';
import 'package:super_collection/features/collection/system_filter_models.dart';
import 'package:super_collection/features/collection/system_filters_repository.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/collection/tag_search_page.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/shell/user_avatar_button.dart';

/// 我的收藏（系统分类 + 标签）
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
    this.onOpenAccount,
  });

  /// 是否为当前 Tab；切回时静默刷新数量。
  final bool isActive;

  /// 外部递增时静默刷新（分享入库、解析完成）。
  final int refreshTick;

  /// 打开账户抽屉。
  final VoidCallback? onOpenAccount;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _text = Color(0xFF1F242E);

  final _tagsRepo = TagsRepository();
  final _tagModulesRepo = TagModulesRepository();
  final _systemFiltersRepo = SystemFiltersRepository();
  final _scrollController = ScrollController();
  final _tagsHeaderKey = GlobalKey();

  List<TagModule> _modules = const [];
  List<Tag> _ungrouped = const [];
  List<SystemFilter> _systemFilters = const [];
  bool _loading = true;
  String? _error;
  /// 归类标签区顶到顶栏：切换顶栏形态
  bool _tagsFocused = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollForTagsFocus);
    _load();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollForTagsFocus);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  void _openTagSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TagSearchPage(),
      ),
    );
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
        _tagModulesRepo.listModules(),
        _systemFiltersRepo.listFilters(),
      ]);
      if (!mounted) return;
      final modulesResult =
          results[0] as ({List<TagModule> modules, List<Tag> ungrouped});
      final filterResult =
          results[1] as ({List<SystemFilter> filters, List<SystemFilter> others});
      setState(() {
        _modules = modulesResult.modules;
        _ungrouped = modulesResult.ungrouped;
        _systemFilters = filterResult.filters;
        _loading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onScrollForTagsFocus();
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

  void _onScrollForTagsFocus() {
    final ctx = _tagsHeaderKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final threshold = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // 滞回：避免顶栏切换时 header 高度变化导致焦点抖动
    final focused = _tagsFocused
        ? top <= threshold + 28
        : top <= threshold + 4;
    if (focused == _tagsFocused) return;
    setState(() {
      _tagsFocused = focused;
    });
  }

  Future<void> _exitTagsFocus() async {
    setState(() {
      _tagsFocused = false;
    });
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _createModule() async {
    final module = await showCreateModuleSheet(context);
    if (module == null || !mounted) return;
    await _load(quiet: true);
  }

  Future<void> _addTagToModule(int? moduleId) async {
    final tag = await showCreateTagSheet(context, moduleId: moduleId);
    if (tag == null || !mounted) return;
    await _load(quiet: true);
  }

  void _openSystemFilter(SystemFilter filter) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => SystemFilterListPage(
          code: filter.code,
          title: filter.name,
        ),
      ),
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  void _openTag(Tag tag) {
    Navigator.of(context)
        .push(
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
    )
        .then((_) {
      if (mounted) _load(quiet: true);
    });
  }

  PreferredSizeWidget _buildAppBar() {
    if (_tagsFocused) {
      return AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: '返回',
          onPressed: _exitTagsFocus,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        ),
        title: const Text(
          '归类标签',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: _text,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '新建模块',
            onPressed: _createModule,
            icon: const Icon(
              Icons.add_rounded,
              size: 24,
              color: Color(0xFF2F6FED),
            ),
          ),
          const SizedBox(width: 4),
        ],
      );
    }

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
      title: SizedBox(
        width: MediaQuery.sizeOf(context).width,
        height: 40,
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Row(
            children: [
              UserAvatarButton(
                onPressed: widget.onOpenAccount ?? () {},
              ),
              const Spacer(),
              IconButton(
                tooltip: '搜索标签',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
                onPressed: _openTagSearch,
                icon: SvgPicture.asset(
                  'assets/icons/search.svg',
                  width: 24,
                  height: 24,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: const <Widget>[],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          controller: _scrollController,
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
            else ...[
              if (_systemFilters.isNotEmpty)
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
              if (_systemFilters.isNotEmpty) const SizedBox(height: 28),
              CollectionTagModulesSection(
                headerKey: _tagsHeaderKey,
                modules: _modules,
                ungrouped: _ungrouped,
                showInlineHeader: !_tagsFocused,
                onOpenTag: _openTag,
                onAddTag: _addTagToModule,
                onCreateModule: _createModule,
              ),
              // 便于上滑把归类标签顶到顶栏
              SizedBox(height: MediaQuery.sizeOf(context).height * 0.45),
            ],
          ],
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
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: icon.background,
                  borderRadius: BorderRadius.circular(7),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon.icon,
                  size: 16,
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
