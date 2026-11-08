import 'package:flutter/material.dart';
import 'package:super_collection/features/agent/agent_host.dart';
import 'package:super_collection/features/agent/agent_panel_slot.dart';
import 'package:super_collection/features/shell/app_side_nav.dart';

/// 三列场景：`list | (agent) | detail`。
/// 助手宽 = 侧栏 + 列表，整块顶入；阅读列开合前后宽度不变。
class AgentSplitInset extends StatelessWidget {
  const AgentSplitInset({
    super.key,
    required this.listWidth,
    required this.list,
    required this.detail,
    this.listDecoration,
    this.active = true,
  });

  final double listWidth;
  final Widget list;
  final Widget detail;
  final BoxDecoration? listDecoration;

  /// 当前 Tab 可见时才承接助手，避免 IndexedStack 里多份面板。
  final bool active;

  static const _anim = Duration(milliseconds: 340);
  static const _curve = Curves.easeOutCubic;
  static const _hairline = Color(0xFFE9EBEF);

  /// 与前两列合计等宽，保证第三列不被挤。
  static double panelWidthFor(double listWidth) =>
      AppSideNav.width + listWidth;

  @override
  Widget build(BuildContext context) {
    final host = AgentHost.maybeOf(context);
    final open = active && (host?.splitOpen ?? false);
    final showPanel = active && (host?.showSplitPanel ?? false);
    final panel = showPanel ? host!.panel : null;
    final panelW = panelWidthFor(listWidth);

    return LayoutBuilder(
      builder: (context, constraints) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: open ? 1 : 0),
          duration: _anim,
          curve: _curve,
          child: panel,
          builder: (context, t, child) {
            final total = constraints.maxWidth;
            // 主壳同步收起侧栏时，本区变宽 absorbedNav。
            final absorbedNav = AppSideNav.width * t;
            final panelSlotW = child != null ? panelW * t : 0.0;
            final listW = listWidth * (1 - t);
            // panelW == list + nav ⇒ leadingW = list*(1-t)，reading 恒为 total - list - absorbedNav。
            final leadingW =
                (listWidth + absorbedNav - panelSlotW).clamp(0.0, total);
            final readingW =
                (total - leadingW - panelSlotW).clamp(0.0, total);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: leadingW,
                  child: listW > 0.5
                      ? ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: listWidth,
                            maxWidth: listWidth,
                            child: SizedBox(
                              width: listWidth,
                              child: DecoratedBox(
                                decoration: listDecoration ??
                                    const BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: _hairline),
                                      ),
                                    ),
                                child: list,
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (child != null)
                  AgentPanelSlot(
                    progress: t,
                    width: panelW,
                    alignment: Alignment.centerLeft,
                    edgeColor: _hairline,
                    showLeftEdge: true,
                    showRightEdge: true,
                    child: child,
                  ),
                SizedBox(
                  width: readingW,
                  child: ClipRect(child: detail),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
