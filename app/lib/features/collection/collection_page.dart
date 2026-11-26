import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:super_collection/core/network/api_client.dart';
import 'package:super_collection/core/ui/app_confirm_dialog.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/core/ui/app_toast.dart';
import 'package:super_collection/features/agent/agent_host.dart';
import 'package:super_collection/features/agent/agent_spark_label.dart';
import 'package:super_collection/features/auth/auth_repository.dart';
import 'package:super_collection/features/collection/collection_tag_modules_section.dart';
import 'package:super_collection/features/collection/create_module_sheet.dart';
import 'package:super_collection/features/collection/create_tag_sheet.dart';
import 'package:super_collection/features/collection/items_browse_page.dart';
import 'package:super_collection/features/collection/tag_models.dart';
import 'package:super_collection/features/collection/tag_module_models.dart';
import 'package:super_collection/features/collection/tag_modules_repository.dart';
import 'package:super_collection/features/collection/tags_repository.dart';
import 'package:super_collection/features/onboarding/home_coach_overlay.dart';
import 'package:super_collection/features/onboarding/tag_coach_prefs.dart';
import 'package:super_collection/features/shell/tablet_items_split.dart';
import 'package:super_collection/features/shell/user_avatar_button.dart';

/// 标签（归类整理）
class CollectionPage extends StatefulWidget {
  const CollectionPage({
    super.key,
    this.isActive = true,
    this.refreshTick = 0,
    this.onOpenAccount,
    this.onTabletSplitChanged,
  });

  /// 是否为当前 Tab；切回时静默刷新数量。
  final bool isActive;

  /// 外部递增时静默刷新（分享入库、解析完成）。
  final int refreshTick;

  /// 打开账户抽屉。
  final VoidCallback? onOpenAccount;

  /// iPad：进入/退出列表|阅读浏览态（三列）时通知主壳，以便助手从缝顶入。
  final ValueChanged<bool>? onTabletSplitChanged;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  static const _bg = Color(0xFFF7F7FA);
  static const _blue = Color(0xFF2F6FED);

  /// 引导：+新建 →（空库）添加 → 点选 → 短拖 → 长按挂下级 → 下钻子层。
  static const _stepCreate = 0;
  static const _stepAddTag = 1;
  static const _stepSelect = 2;
  static const _stepShortDrag = 3;
  static const _stepLongPress = 4;
  static const _stepLinks = 5;

  final _tagsRepo = TagsRepository();
  final _tagModulesRepo = TagModulesRepository();
  final _auth = AuthRepository();

  final _createModuleKey = GlobalKey();
  final _addTagKey = GlobalKey();
  final _sampleTagKey = GlobalKey();

  List<TagModule> _modules = const [];
  List<Tag> _ungrouped = const [];
  bool _loading = true;
  String? _error;

  /// iPad 浏览态：点分类/标签后切三列；null=枢纽。
  _TabletBrowse? _tabletBrowse;
  int _tabletBrowseTick = 0;

  int? _coachStep;
  int? _coachUserId;
  OverlayEntry? _coachOverlay;
  bool _coachStarting = false;
  /// 开导时是否需要「添加标签」步（用于步数文案）。
  bool _coachIncludeAddTag = false;

  bool get _hubEmpty => _modules.isEmpty && _ungrouped.isEmpty;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.isActive) unawaited(_maybeStartCoach());
    });
  }

  @override
  void dispose() {
    _removeCoachOverlay();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CollectionPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _load(quiet: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_maybeStartCoach());
      });
    }
    if (!widget.isActive && oldWidget.isActive) {
      _removeCoachOverlay();
      _coachStep = null;
    }
    if (widget.refreshTick != oldWidget.refreshTick) {
      _load(quiet: true);
    }
  }

  Future<void> _load({bool quiet = false}) async {
    final showSpinner = !quiet || _hubEmpty;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final modulesResult = await _tagModulesRepo.listModules();
      if (!mounted) return;
      setState(() {
        _modules = modulesResult.modules;
        _ungrouped = modulesResult.ungrouped;
        _loading = false;
        _error = null;
      });
      if (widget.isActive) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_maybeStartCoach());
        });
      }
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

  /// 当前选中标签；`null` = 顶层新建
  int? _createParentId;

  /// 右上角「+」：有选中则挂其下，否则顶层新建
  Future<void> _createAtCurrentLevel() async {
    if (_coachStep != null) return;
    await _addTagToModule(_createParentId);
  }

  Future<void> _maybeStartCoach() async {
    if (!mounted ||
        !widget.isActive ||
        _coachStarting ||
        _coachStep != null ||
        _tabletBrowse != null ||
        _loading ||
        _error != null) {
      return;
    }
    _coachStarting = true;
    try {
      final session = await _auth.readSession();
      _coachUserId = session?.userId;
      final seen = await TagCoachPrefs.isSeen(userId: _coachUserId);
      if (!mounted || seen || !widget.isActive || _tabletBrowse != null) {
        return;
      }
      _coachIncludeAddTag = _hubEmpty;
      final first = _nextValidStep(_stepCreate);
      if (first == null) return;
      _coachStep = first;
      _syncCoachOverlay();
    } finally {
      _coachStarting = false;
    }
  }

  void _removeCoachOverlay() {
    _coachOverlay?.remove();
    _coachOverlay = null;
  }

  void _syncCoachOverlay() {
    _removeCoachOverlay();
    if (_coachStep == null || !mounted) return;
    _coachOverlay = OverlayEntry(builder: (context) => _buildCoachLayer());
    Overlay.of(context).insert(_coachOverlay!);
  }

  void _rebuildCoachOverlay() {
    _coachOverlay?.markNeedsBuild();
  }

  Future<void> _finishCoach() async {
    _removeCoachOverlay();
    _coachStep = null;
    await TagCoachPrefs.markSeen(userId: _coachUserId);
  }

  /// 有标签则跳过「添加」；无标签则跳过点选及之后需样例的步骤。
  bool _coachStepSkipped(int step) {
    if (step == _stepAddTag && !_hubEmpty) return true;
    if (step >= _stepSelect && step <= _stepLinks && _hubEmpty) return true;
    return false;
  }

  int? _nextValidStep(int fromInclusive) {
    for (var s = fromInclusive; s <= _stepLinks; s++) {
      if (_coachStepSkipped(s)) continue;
      return s;
    }
    return null;
  }

  void _coachNext() {
    final step = _coachStep;
    if (step == null) return;
    final next = _nextValidStep(step + 1);
    if (next == null) {
      unawaited(_finishCoach());
      return;
    }
    _coachStep = next;
    _syncCoachOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuildCoachOverlay();
    });
  }

  int _coachDisplayIndex(int step) {
    var i = 0;
    for (var s = 0; s <= step; s++) {
      if (s == _stepAddTag && !_coachIncludeAddTag) continue;
      if (s >= _stepSelect && s <= _stepLinks && _hubEmpty) continue;
      i++;
    }
    return i;
  }

  int get _coachDisplayTotal {
    var n = 0;
    for (var s = 0; s <= _stepLinks; s++) {
      if (s == _stepAddTag && !_coachIncludeAddTag) continue;
      if (s >= _stepSelect && s <= _stepLinks && _hubEmpty) continue;
      n++;
    }
    return n;
  }

  double _tooltipTop(Rect hole, Size screen) {
    const tipH = 210.0;
    final below = hole.bottom + 14;
    if (below + tipH < screen.height - 88) return below;
    return (hole.top - tipH - 12).clamp(24.0, screen.height - tipH - 24);
  }

  Widget _buildCoachLayer() {
    final step = _coachStep;
    if (step == null) return const SizedBox.shrink();
    final screen = MediaQuery.sizeOf(context);

    // 走到需样例的步骤却仍无标签：自动收尾。
    if (step >= _stepSelect && step <= _stepLinks && _hubEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _coachStep == step) unawaited(_finishCoach());
      });
      return const SizedBox.shrink();
    }

    GlobalKey targetKey;
    String title;
    String message;
    String confirm;
    var holeRadius = 12.0;
    var inflate = 6.0;
    switch (step) {
      case _stepCreate:
        targetKey = _createModuleKey;
        title = '添加标签';
        message = '点右上角「+」新建标签；若已点选某个标签，新建会挂到它下面。';
        confirm = '下一步';
        holeRadius = 18;
        inflate = 4;
      case _stepAddTag:
        targetKey = _addTagKey;
        title = '添加标签';
        message = '还没有标签。先点「添加标签」建一个。';
        confirm = '下一步';
        holeRadius = 14;
      case _stepSelect:
        targetKey = _sampleTagKey;
        title = '点选标签';
        message = '点标签后，底栏可「看收藏」或「看子层」；要加子标签点右上角「+」。有下级的圆点更大。';
        confirm = '下一步';
        holeRadius = 14;
        inflate = 10;
      case _stepShortDrag:
        targetKey = _sampleTagKey;
        title = '短拖摆位置';
        message = '按住标签短拖，可以在画布上改位置；双指捏合可缩放。';
        confirm = '下一步';
        holeRadius = 14;
        inflate = 10;
      case _stepLongPress:
        targetKey = _sampleTagKey;
        title = '长按挂下级';
        message = '长按一个标签拖到另一个上，会挂成它的子标签。';
        confirm = '下一步';
        holeRadius = 14;
        inflate = 10;
      default:
        targetKey = _sampleTagKey;
        title = '看子层';
        message = '画布默认只显示当前层。再点已选标签，或点底栏「看子层」，用面包屑返回。';
        confirm = '开始整理';
        holeRadius = 14;
        inflate = 10;
    }

    final hole = rectForKey(targetKey, inflate: inflate);
    if (hole == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _coachStep != step) return;
        // 添加步：用户可能已建好标签，直接跳到拖动。
        if (step == _stepAddTag && !_hubEmpty) {
          _coachNext();
          return;
        }
        _rebuildCoachOverlay();
      });
      return const SizedBox.shrink();
    }

    return CoachHoleOverlay(
      hole: hole,
      holeRadius: holeRadius,
      tooltipTop: _tooltipTop(hole, screen),
      onHoleTap: () {
        if (step == _stepAddTag) {
          unawaited(_addTagDuringCoach());
        } else {
          _coachNext();
        }
      },
      tooltip: CoachTooltipCard(
        stepLabel: '${_coachDisplayIndex(step)} / $_coachDisplayTotal',
        title: title,
        message: message,
        confirmLabel: confirm,
        showSkip: step != _stepLinks,
        onSkip: () => unawaited(_finishCoach()),
        onConfirm: _coachNext,
      ),
    );
  }

  Future<void> _addTagDuringCoach() async {
    await _addTagToModule(null);
    if (!mounted || _coachStep != _stepAddTag) return;
    if (!_hubEmpty) {
      _coachNext();
    } else {
      _rebuildCoachOverlay();
    }
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
      title: '删除标签',
      message: '确定删除「${module.name}」？下级标签会升到上一级，不会删除内容。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await _tagModulesRepo.deleteModule(module.id);
      if (!mounted) return;
      AppToast.show(context, '已删除「${module.name}」');
      await _load(quiet: true);
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(context, '删除失败');
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final ok = await showAppConfirmDialog(
      context,
      title: '删除标签',
      message: '确定删除「${tag.name}」？下级标签会升到上一级；仅解除与条目的关联，不会删除内容。',
      confirmLabel: '删除',
    );
    if (ok != true || !mounted) return;
    try {
      await _tagsRepo.deleteTag(tag.id);
      if (!mounted) return;
      AppToast.show(context, '已删除「${tag.name}」');
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
    if (tag.effectiveParentId == moduleId) return;
    if (moduleId != null && tag.id == moduleId) return;

    try {
      await _tagsRepo.placeTag(tag.id, moduleId: moduleId);
      if (!mounted) return;
      await _load(quiet: true);
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

  void _openTag(Tag tag) {
    if (AppOrientation.isTablet(context)) {
      _setTabletBrowse(
        _TabletBrowse(
          title: tag.name,
          openEntry: 'tag',
          loader: ({required limit, required offset, mediaKind}) =>
              _tagsRepo.listTagItems(
            tag.id,
            limit: limit,
            offset: offset,
          ),
        ),
      );
      return;
    }
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
    if (AppOrientation.isTablet(context)) {
      _setTabletBrowse(
        _TabletBrowse(
          title: module.name,
          openEntry: 'library',
          loader: ({required limit, required offset, mediaKind}) =>
              _tagModulesRepo.listModuleItems(
            module.id,
            limit: limit,
            offset: offset,
          ),
        ),
      );
      return;
    }
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

  void _closeTabletBrowse() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _tabletBrowse = null);
    widget.onTabletSplitChanged?.call(false);
    // 延后刷新，避免首帧重建把刚返回的第一次点击吃掉
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load(quiet: true));
    });
  }

  void _setTabletBrowse(_TabletBrowse browse) {
    setState(() {
      _tabletBrowse = browse;
      _tabletBrowseTick++;
    });
    widget.onTabletSplitChanged?.call(true);
  }

  Future<void> _openAgent() => openAgent(context);

  /// 与首页一致：蓝底圆「+」。
  Widget _buildCreateModuleButton({EdgeInsetsGeometry? padding}) {
    final button = IconButton(
      key: _createModuleKey,
      tooltip: '添加标签',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      onPressed: () => unawaited(_createAtCurrentLevel()),
      icon: Container(
        width: 32,
        height: 32,
        decoration: const BoxDecoration(
          color: _blue,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/icons/add.svg',
          width: 18,
          height: 18,
          colorFilter: const ColorFilter.mode(
            Colors.white,
            BlendMode.srcIn,
          ),
        ),
      ),
    );
    if (padding == null) return button;
    return Padding(padding: padding, child: button);
  }

  PreferredSizeWidget _buildAppBar() {
    // 头像放 leading；右上与首页同序：助手 → +
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 56,
      titleSpacing: 0,
      actionsPadding: EdgeInsets.zero,
      automaticallyImplyLeading: false,
      leadingWidth: 56,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: UserAvatarButton(
          onPressed: widget.onOpenAccount ?? () {},
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(
            onPressed: () => unawaited(_openAgent()),
            style: TextButton.styleFrom(
              foregroundColor: _blue,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const AgentSparkLabel(),
          ),
        ),
        _buildCreateModuleButton(
          padding: const EdgeInsets.only(right: 8),
        ),
      ],
    );
  }

  Widget _buildHubBody({required bool tablet}) {
    // 满屏画布优先：去掉下拉刷新，避免与 InteractiveViewer 纵向拖拽抢手势。
    return CustomScrollView(
      physics: const NeverScrollableScrollPhysics(),
      slivers: [
        if (tablet)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Align(
                alignment: Alignment.centerRight,
                child: _buildCreateModuleButton(),
              ),
            ),
          ),
        if (_loading && _hubEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (_error != null && _hubEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: _ErrorCard(message: _error!, onRetry: _load),
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              const gapAboveNav = 28.0;
              final bottomPad =
                  gapAboveNav + MediaQuery.paddingOf(context).bottom;
              final minH = (constraints.remainingPaintExtent - bottomPad)
                  .clamp(0.0, double.infinity);
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
                sliver: SliverToBoxAdapter(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minH),
                    child: CollectionTagModulesSection(
                      modules: _modules,
                      ungrouped: _ungrouped,
                      showHeader: false,
                      bodyOnly: false,
                      fillRemaining: true,
                      addTagKey: _addTagKey,
                      sampleTagKey: _sampleTagKey,
                      onOpenTag: _openTag,
                      onOpenModule: _openModule,
                      onAddTag: _addTagToModule,
                      onRenameModule: _renameModule,
                      onDeleteModule: _deleteModule,
                      onDeleteTag: _deleteTag,
                      onCreateModule: _createAtCurrentLevel,
                      onPathParentChanged: (parentId) {
                        _createParentId = parentId;
                      },
                      onPlaceTag: _placeTag,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tablet = AppOrientation.isTablet(context);
    final browse = _tabletBrowse;
    if (tablet && browse != null) {
      return TabletItemsSplit(
        key: ValueKey('browse-${browse.title}-$_tabletBrowseTick'),
        title: browse.title,
        loader: browse.loader,
        openEntry: browse.openEntry,
        onBack: _closeTabletBrowse,
        refreshTick: widget.refreshTick + _tabletBrowseTick,
      );
    }

    // 新建归类等弹层自己避让键盘；避免灰底随 inset 抬起露在遮罩外
    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false,
      appBar: tablet ? null : _buildAppBar(),
      body: _buildHubBody(tablet: tablet),
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
        borderRadius: BorderRadius.circular(16),
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

abstract final class _CollectionColors {
  static const muted = Color(0xFF737A85);
}

class _TabletBrowse {
  const _TabletBrowse({
    required this.title,
    required this.loader,
    required this.openEntry,
  });

  final String title;
  final TabletItemsLoader loader;
  final String openEntry;
}
