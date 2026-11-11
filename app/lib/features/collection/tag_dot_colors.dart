import 'package:flutter/material.dart';

/// 标签/归类色：按归类 id 稳定取色；未归类用中性色。
abstract final class TagDotColors {
  static const ungrouped = Color(0xFF5C6675);

  static const palette = <Color>[
    Color(0xFF5B7FB8),
    Color(0xFF5A9A90),
    Color(0xFF7A86B8),
    Color(0xFF6A98A8),
    Color(0xFF8A7EAE),
    Color(0xFF5E8A96),
    Color(0xFF7D9474),
    Color(0xFFB49A78),
    Color(0xFFB88490),
    Color(0xFF6A8F7A),
    Color(0xFFA89068),
    Color(0xFF6E8FA8),
  ];

  static Color forModule(int? moduleId) {
    if (moduleId == null) return ungrouped;
    final id = moduleId < 0 ? -moduleId : moduleId;
    return palette[id % palette.length];
  }
}
