import 'package:flutter/material.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/collection/ai_organize_sheet.dart';
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
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';
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
  /// 归类标签收进顶栏：0 未贴顶，1 完全收起
  final _tagsFocusT = ValueNotifier<double>(0);

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
    _tagsFocusT.dispose();
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
        _systemFilters = filterResult.filters
            .where((f) => f.code != 'unread' && f.code != 'recent_read')
            .toList(growable: false);
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
    final dock = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // 贴顶前约一栏高度内完成过渡，避免布尔切换的硬切
    const range = 56.0;
    final next = ((dock + 8 - top) / range).clamp(0.0, 1.0);
    if ((next - _tagsFocusT.value).abs() < 0.008) return;
    _tagsFocusT.value = next;
  }

  Future<void> _exitTagsFocus() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _createModule() async {
    final module = await showCreateModuleSheet(context);
    if (module == null || !mounted) return;
    await _load(quiet: true);
  }

  Future<void> _renameModule(TagModule module) async {
    final updated = await showRenameModuleSheet(context, module: module);
    if (updated == null || !mounted) return;
    await _load(quiet: true);
  }

  Future<void> _addTagToModule(int? moduleId) async {
    final tag = await showCreateTagSheet(context, moduleId: moduleId);
    if (tag == null || !mounted) return;
    await _load(quiet: true);
  }

  Future<void> _deleteModule(TagModule module) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除归类',
      message: '确定删除归类「${module.name}」？组内标签会回到未归类，不会删除标签。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await _tagModulesRepo.deleteModule(module.id);
      if (!mounted) return;
      AppToast.show(context, '已删除归类「${module.name}」');
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '删除失败');
    }
  }

  Future<void> _placeTag(Tag tag, int? moduleId) async {
    if (tag.moduleId == moduleId) return;

    final moved = moduleId == null
        ? tag.copyWith(clearModuleId: true)
        : tag.copyWith(moduleId: moduleId);

    setState(() {
      var nextUngrouped = List<Tag>.from(_ungrouped);
      var nextModules = _modules
          .map((m) => m.copyWith(tags: List<Tag>.from(m.tags)))
          .toList();

      if (tag.moduleId == null) {
        nextUngrouped.removeWhere((t) => t.id == tag.id);
      } else {
        nextModules = nextModules.map((m) {
          if (m.id != tag.moduleId) return m;
          return m.copyWith(
            tags: m.tags.where((t) => t.id != tag.id).toList(),
          );
        }).toList();
      }

      if (moduleId == null) {
        nextUngrouped = [...nextUngrouped, moved];
      } else {
        nextModules = nextModules.map((m) {
          if (m.id != moduleId) return m;
          return m.copyWith(tags: [...m.tags, moved]);
        }).toList();
      }

      _ungrouped = nextUngrouped;
      _modules = nextModules;
    });

    try {
      await _tagsRepo.placeTag(tag.id, moduleId: moduleId);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
      await _load(quiet: true);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '移动失败');
      await _load(quiet: true);
    }
  }

  Future<void> _aiOrganize() async {
    final tagCount = _ungrouped.length +
        _modules.fold<int>(0, (n, m) => n + m.tags.length);
    if (tagCount < 2) {
      AppToast.show(context, '至少需要 2 个标签才能 AI 标签归类');
      return;
    }
    final allowed = await ensurePlanFeatures(
      context,
      requirements: [
        (has: (f) => f.aiOrganize, tier: UsagePlan.prince),
      ],
    );
    if (!allowed || !mounted) return;
    final ok = await showAiOrganizeSheet(context);
    if (ok == true && mounted) {
      await _load(quiet: true);
    }
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

  void _openModule(TagModule module) {
    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => ItemsBrowsePage(
          title: module.name,
          loader: ({required limit, required offset}) =>
              _tagModulesRepo.listModuleItems(
            module.id,
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
      title: AnimatedBuilder(
        animation: _tagsFocusT,
        builder: (context, _) {
          final t = Curves.easeInOutCubic.transform(_tagsFocusT.value);
          return SizedBox(
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                IgnorePointer(
                  ignoring: t > 0.45,
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, right: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: UserAvatarButton(
                          onPressed: widget.onOpenAccount ?? () {},
                        ),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: t < 0.45,
                  child: Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - t)),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: '返回',
                            onPressed: _exitTagsFocus,
                            icon: const Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 20,
                            ),
                          ),
                          const Expanded(
                            child: Text(
                              '归类标签',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: _text,
                              ),
                            ),
                          ),
                          CollectionCreateModuleButton(
                            onPressed: _createModule,
                            iconPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
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
                _EntityGroup(
                  entries: [
                    for (final f in _systemFilters)
                      _EntityEntry(
                        title: f.name,
                        countLabel: f.countLabel,
                        icon: _CollectionNavIcon.forSystemCode(f.code),
                        onTap: () => _openSystemFilter(f),
                      ),
                  ],
                ),
              if (_systemFilters.isNotEmpty) const SizedBox(height: 28),
              CollectionTagModulesSection(
                headerKey: _tagsHeaderKey,
                modules: _modules,
                ungrouped: _ungrouped,
                headerCollapse: _tagsFocusT,
                onOpenTag: _openTag,
                onOpenModule: _openModule,
                onAddTag: _addTagToModule,
                onRenameModule: _renameModule,
                onDeleteModule: _deleteModule,
                onCreateModule: _createModule,
                onAiOrganize: _aiOrganize,
                onPlaceTag: _placeTag,
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
      case 'untagged':
        return const _CollectionNavIcon(
          icon: Icons.label_off_outlined,
          background: Color(0xFF8B929C),
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
