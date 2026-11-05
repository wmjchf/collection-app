import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_collection/features/items/items_layout_prefs.dart';

/// 「共 N 条」右侧：左单列 / 右双列，选中态高亮，一眼可点。
class ItemsLayoutToggleButton extends StatelessWidget {
  const ItemsLayoutToggleButton({
    super.key,
    this.enabled = true,
    this.layoutPrefs,
  });

  final bool enabled;

  /// 缺省全局偏好；首页整库传 [ItemsLayoutPrefs.homeLibrary]。
  final ItemsLayoutPrefs? layoutPrefs;

  static const _muted = Color(0xFF9AA0A8);
  static const _track = Color(0xFFF0F2F5);
  static const _selectedFill = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2F6FED);

  @override
  Widget build(BuildContext context) {
    final prefs = layoutPrefs ?? ItemsLayoutPrefs.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (context, _) {
        final mode = prefs.mode;
        return Opacity(
          opacity: enabled ? 1 : 0.45,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _track,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Segment(
                    icon: Icons.view_agenda_outlined,
                    selected: mode == ItemsLayoutMode.list,
                    tooltip: '单列列表',
                    enabled: enabled,
                    onTap: () {
                      unawaited(prefs.setMode(ItemsLayoutMode.list));
                    },
                  ),
                  _Segment(
                    icon: Icons.grid_view_rounded,
                    selected: mode == ItemsLayoutMode.masonry,
                    tooltip: '双列瀑布',
                    enabled: enabled,
                    onTap: () {
                      unawaited(prefs.setMode(ItemsLayoutMode.masonry));
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected
            ? ItemsLayoutToggleButton._selectedFill
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        elevation: selected ? 0.5 : 0,
        shadowColor: const Color(0x33000000),
        child: InkWell(
          onTap: enabled && !selected ? onTap : null,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: 30,
            height: 26,
            child: Icon(
              icon,
              size: 16,
              color: selected
                  ? ItemsLayoutToggleButton._accent
                  : ItemsLayoutToggleButton._muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 数量文案 + 右侧布局切换。
class ItemsFeedCountRow extends StatelessWidget {
  const ItemsFeedCountRow({
    super.key,
    required this.label,
    this.enabled = true,
    this.layoutPrefs,
    this.labelStyle = const TextStyle(
      fontSize: 13,
      color: Color(0xFF737A85),
    ),
  });

  final String label;
  final bool enabled;
  final ItemsLayoutPrefs? layoutPrefs;
  final TextStyle labelStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: labelStyle),
        ),
        ItemsLayoutToggleButton(
          enabled: enabled,
          layoutPrefs: layoutPrefs,
        ),
      ],
    );
  }
}
