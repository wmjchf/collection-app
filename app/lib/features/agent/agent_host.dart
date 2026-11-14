import 'package:flutter/material.dart';
import 'package:super_collection/core/ui/app_orientation.dart';
import 'package:super_collection/features/agent/agent_page.dart';
import 'package:super_collection/features/items/item_models.dart';
import 'package:super_collection/features/settings/quota_gate.dart';
import 'package:super_collection/features/settings/usage_repository.dart';

/// iPad 主壳提供 AI Agent面板状态。
///
/// - 两列（收藏枢纽）：侧栏不动，第二列让出定宽，右侧滑入助手
/// - 三列（首页/搜索/收藏浏览）：从列表|阅读缝顶入，侧栏+列表挤没
class AgentHost extends InheritedWidget {
  const AgentHost({
    super.key,
    required this.openPanel,
    required this.closePanel,
    required this.isOpen,
    required this.panelMounted,
    required this.isSplitSurface,
    required this.panel,
    required super.child,
  });

  /// 两列枢纽助手上限；三列用 [AgentSplitInset.panelWidthFor]（= 侧栏+列表）。
  static const panelWidth = 560.0;

  final Future<void> Function({
    int? focusItemId,
    CollectionItem? focusItem,
  }) openPanel;
  final VoidCallback closePanel;

  /// 动画目标：true=展开，false=收起。
  final bool isOpen;

  /// 收起动画结束前仍为 true，避免中途卸面板闪一下。
  final bool panelMounted;

  /// 当前 Tab 是否为列表|阅读三列（与是否打开助手无关）。
  final bool isSplitSurface;

  /// 主壳构建的稳定面板实例（动画用 child 挂载，勿每帧 new）。
  final Widget? panel;

  static AgentHost? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AgentHost>();
  }

  /// 三列缝里是否应展示助手（含收起动画过程）。
  bool get showSplitPanel =>
      isSplitSurface && panelMounted && panel != null;

  /// 三列缝里动画目标。
  bool get splitOpen => isSplitSurface && isOpen;

  @override
  bool updateShouldNotify(AgentHost oldWidget) =>
      openPanel != oldWidget.openPanel ||
      closePanel != oldWidget.closePanel ||
      isOpen != oldWidget.isOpen ||
      panelMounted != oldWidget.panelMounted ||
      isSplitSurface != oldWidget.isSplitSurface ||
      panel != oldWidget.panel;
}

/// 打开 AI Agent：平板按当前列数布局，手机全屏页。
Future<void> openAgent(
  BuildContext context, {
  int? focusItemId,
  CollectionItem? focusItem,
}) async {
  final allowed = await ensurePlanFeatures(
    context,
    requirements: [
      (has: (f) => f.aiAgent, tier: UsagePlan.prince),
    ],
  );
  if (!allowed || !context.mounted) return;

  final host = AgentHost.maybeOf(context);
  if (host != null && AppOrientation.isTablet(context)) {
    await host.openPanel(
      focusItemId: focusItemId,
      focusItem: focusItem,
    );
    return;
  }

  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AgentPage(
        focusItemId: focusItemId,
        focusItem: focusItem,
      ),
    ),
  );
}
